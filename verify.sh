#!/bin/bash
# verify.sh — verifier 唯一入口
#
#   ./verify.sh            验最新发布的那一版
#   ./verify.sh v0.2.0     验指定版本
#
# 从公开材料重建整条链，逐项跟 measurements.jsonl 里那一行声明的值比对：
#   gateway 二进制 → rootfs(erofs+verity) → roothash → UKI → RTMR1/RTMR2
#
# 任何一项对不上就退出。全部对上，说明那一行声明是可复现的，剩下的是拿
# RTMR1/RTMR2 跟 prover 的 quote 比（见 README 的 TODO）。
set -e
cd "$(dirname "$0")"

# measurements.jsonl 一行一次发布，只追加不改既有行。所以它同时是「验哪一版」
# 的输入和一份公开的历史记录 —— git 上每次发布的 diff 就是「加了一行」。
M=measurements.jsonl
[ -f "$M" ] || { echo "缺 $M —— 这个仓库还没有发布过任何版本"; exit 1; }

if [ -n "${1:-}" ]; then
  # 只追加不去重，所以 version 理论上可能重复。重复了就说明有人发重了，
  # 那种情况下随便挑一条都是错的，直接停。
  N=$(jq -s --arg v "$1" 'map(select(.version==$v)) | length' "$M")
  [ "$N" = 1 ] \
    || { echo "$M 里 version=$1 有 $N 条，应为 1"; exit 1; }
  ROW=$(jq -c --arg v "$1" 'select(.version==$v)' "$M")
else
  ROW=$(tail -n1 "$M")
fi
j() { printf '%s' "$ROW" | jq -r ".$1"; }

VERSION=$(j version)
DATA=$(j verity_data_dev)
HASH=$(j verity_hash_dev)
STUB=./zeroseal-linuxx64.efi.stub

echo "=== 验证 ${VERSION}（发布于 $(j released_at)）==="

echo "=== [0/5] 准备 tools 树 ==="
# tools 树是 330 MB 的 Ubuntu 包快照，没进 git —— mkosi.tools.manifest 里
# snapshot: null，光靠包清单复现不出 bit-identical 的树，所以树本身要单独发。
#
# 它决定 rootfs 里装了哪些包的哪些版本，换一棵树 roothash 就变，所以必须校验
# 哈希。以前手动下的那份也从来没校验过，那是个洞。
if [ ! -d mkosi.tools ]; then
  if [ ! -f mkosi.tools.tar.gz ]; then
    echo "缺 mkosi.tools.tar.gz（330 MB，没进 git）"
    echo "  来源：$(j tools_url)"
    # 非交互环境（CI、管道）里 read 会挂住，直接给指引退出。
    if [ ! -t 0 ]; then
      echo "  非交互环境，自己下好放到仓库根目录再重跑。"
      exit 1
    fi
    printf "  现在替你下载吗？[y/N] "
    read -r ans
    case "$ans" in
      [yY]*) ;;
      *) echo "  取消。下好放到仓库根目录再重跑。"; exit 1 ;;
    esac
    # -f 让 HTTP 错误算失败（默认会把 404 页面存成文件），-L 跟 GitHub 的重定向。
    # 下一半断了要删掉，否则下次重跑会拿半个文件去校验，报的是哈希不符而不是下载失败。
    curl -fL --progress-bar -o mkosi.tools.tar.gz "$(j tools_url)" \
      || { rm -f mkosi.tools.tar.gz; echo "下载失败"; exit 1; }
  fi

  GOT=$(sha256sum mkosi.tools.tar.gz | cut -d' ' -f1)
  [ "$GOT" = "$(j tools_sha256)" ] \
    || { echo "tools 树哈希不符："; echo "  本地：$GOT"; echo "  声明：$(j tools_sha256)"; exit 1; }
  echo "tools: $GOT ✓"

  tar xzf mkosi.tools.tar.gz
  echo "解压完成"
else
  # 已经解开过就跳过，重跑不必再哈希 330 MB。要强制重校验就删掉 mkosi.tools/。
  echo "mkosi.tools/ 已存在，跳过校验（要重新校验就删掉它）"
fi

echo "=== [1/5] 从源码编译 gateway ==="
# Go 版本必须一致：不同版本的编译器产出不同的二进制，roothash 跟着不同。
# 这一条以前不在验证范围里，是复现论证的一个洞。
WANT_GO=$(j go_version)
HAVE_GO=$(go env GOVERSION)
[ "$HAVE_GO" = "$WANT_GO" ] \
  || { echo "Go 版本不符：本机 $HAVE_GO，需要 $WANT_GO"; exit 1; }

# 构建参数写在这里而不是从 release.json eval —— eval 一个 manifest 里的字符串
# 等于让被验的一方决定验证者执行什么。改成反过来：这里定义，跟 manifest 比对，
# 对不上就停。三个 flag 各自的理由：
#   -trimpath      去掉绝对路径，不同机器上编译才可能一致
#   -buildvcs=false Go 默认把 git 元信息烘进二进制，而 VCS 探测在不同 checkout
#                  形态下结果不同，同一份源码会得到不同二进制
#   GOWORK=off     防止本地 go.work 把依赖记成工作区模块，那也会进 buildinfo
BUILD_ENV=(GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOFLAGS= GOWORK=off)
BUILD_ARGS=(-trimpath -buildvcs=false)
BUILD_CMD="${BUILD_ENV[*]} go build ${BUILD_ARGS[*]}"
[ "$BUILD_CMD" = "$(j build_cmd)" ] \
  || { echo "构建命令与 release.json 声明的不一致："; echo "  本脚本：$BUILD_CMD"; echo "  manifest: $(j build_cmd)"; exit 1; }

rm -rf gateway-src
# 🤔：gateway_repo 来自 release.json
git clone --quiet "$(j gateway_repo)" gateway-src
git -C gateway-src checkout --quiet "$(j gateway_commit)"

# git 存不了空目录，而实际部署的 overlay 里有一个空的 usr/lib/udev/rules.d。
# 它多半是 no-op（udev 包本来就会建这个目录），但「多半」不够 —— 在这里补出来，
# 让 overlay 跟部署的那份完全相等，省掉一个无法从仓库看出来的差异。
mkdir -p overlay/usr/lib/udev/rules.d
mkdir -p overlay/usr/local/bin
( cd gateway-src/gateway \
  && env "${BUILD_ENV[@]}" go build "${BUILD_ARGS[@]}" \
       -o ../../overlay/usr/local/bin/gateway ./cmd/gateway )

GOT=$(sha256sum overlay/usr/local/bin/gateway | cut -d' ' -f1)
[ "$GOT" = "$(j gateway_sha256)" ] \
  || { echo "gateway sha256 不符："; echo "  编出来：$GOT"; echo "  声明的：$(j gateway_sha256)"; exit 1; }
echo "gateway: $GOT ✓"

echo "=== [2/5] 复现 shim / grub / stub ==="
./build-grub-shim.sh
for n in shim grub; do
  got=$(sha256sum "zeroseal-${n}x64.efi" | cut -d' ' -f1)
  want=$(j "${n}_sha256")
  [ "$got" = "$want" ] || { echo "$n sha256 不符："; echo "  复现：$got"; echo "  声明：$want"; exit 1; }
  echo "$n: $got ✓"
done
# stub 同样从 snapshot 抽，不读宿主机的 systemd-boot-efi —— 那份随 apt 升级会变，
# 且验证者的版本跟我们不同就必然对不上。它的字节原样进 UKI，所以必须钉死。
# 没有 stub_sha256 可比，它的正确性由下一步的 uki_sha256 兜住。
./build-stub.sh
echo "stub: $(sha256sum "$STUB" | cut -d' ' -f1) ✓"

echo "=== [3/5] mkosi 复现构建 ==="
( . ~/mkosi-venv/bin/activate && mkosi --force build 2>&1 | tail -3 )
RH=$(cat zeroseal.roothash)
[ "$RH" = "$(j roothash)" ] \
  || { echo "roothash 不符："; echo "  复现：$RH"; echo "  声明：$(j roothash)"; exit 1; }
echo "roothash: $RH ✓"

echo "=== [4/5] 复现 UKI ==="
CMDLINE="systemd.verity=1 roothash=$RH systemd.verity_root_data=$DATA systemd.verity_root_hash=$HASH systemd.verity_root_options=panic-on-corruption console=tty0 console=ttyS0,115200n8 net.ifnames=0 nvme_core.io_timeout=4294967295 iommu=pt"
ukify build --linux=zeroseal.vmlinuz --initrd=zeroseal.initrd --cmdline="$CMDLINE" --stub="$STUB" --output=zeroseal.efi >/dev/null
UKI=$(sha256sum zeroseal.efi | cut -d' ' -f1)
[ "$UKI" = "$(j uki_sha256)" ] \
  || { echo "UKI sha256 不符："; echo "  复现：$UKI"; echo "  声明：$(j uki_sha256)"; echo "  （stub 已由 build-stub.sh 钉死，若这里不符，查 ukify 版本）"; exit 1; }
echo "UKI: $UKI ✓"

echo "=== [5/5] 期望 RTMR ==="
python3 rtmr1.py zeroseal-shimx64.efi zeroseal-grubx64.efi zeroseal.vmlinuz
python3 rtmr2.py zeroseal-shimx64.efi zeroseal.efi zeroseal.initrd
echo
echo "上面五项都对上了，说明 $VERSION 的声明是可复现的。"
echo "↑ RTMR1/RTMR2 与 prover 的 quote 比对（下一步 verify-quote 接验签 + 逐项）。"
