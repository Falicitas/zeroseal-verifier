# zeroseal-verifier

ZeroSeal 的 TDX 远程证明验证器 / A verifier for ZeroSeal's TDX remote attestation.

[中文](#中文) · [English](#english)

---

## 中文

### 这是什么

这个仓库包含一个 shell 脚本与脚本所用的一切配方，旨在让验证方在不需要信任，即零信任下确认 zeroseal 提供的中转服务正在运行的是[这套程序（以下简称 RPg）](https://github.com/Falicitas/zeroseal-gateway)，以及确认运行程序的完整 Linux OS。在你的 Linux 环境下运行 `./verify.sh`，将生成一个崭新的未挂载的 Linux OS，这个 OS 涵盖 RPg。最后我们利用可信执行环境（TEE）的能力，在零信任下让验证方确认 zeroseal 目前对外提供的服务的运行中的 OS 正是验证方自己独立手动生成的 OS。

### 构建环境

你的 Linux 环境不需要使用 TDX 硬件。具体参考环境如下：

- Ubuntu 24.04 LTS（noble）
- （必须）x86_64
- 干净容器。PATH 里若有自己编的 mkosi 或 ukify 会被优先取用，大概率会算出不一样的结果
- 20 GB 空闲磁盘。tools 树解开 1.3 GB，mkosi 产出的 rootfs、erofs、verity 合计约 2 GB，Go 工具链与编译缓存占 1 GB
- 2 vCPU / 4 GB 内存
- 网络环境能连 Ubuntu 官方源与 snapshot 服务、GitHub、Go module proxy
- （必须）全程 root。mkosi 要组 rootfs，而 Ubuntu 24.04 默认关掉了非特权 user namespace
  （`kernel.apparmor_restrict_unprivileged_userns=1`）

### 依赖包安装

管理包：

```bash
# Debian / Ubuntu
apt install -y git jq curl python3-venv python3-pefile systemd-ukify

# Arch
pacman -S --needed git jq curl systemd-ukify python-pefile

# Fedora
dnf install -y git jq curl systemd-ukify python3-pefile
```

| 包             | 作用                                                     |
| -------------- | -------------------------------------------------------- |
| git            | 拉仓库                                                   |
| jq             | 脚本解 JSON                                              |
| python3-venv   | 建 venv，装 mkosi                                        |
| python3-pefile | rtmr1.py / rtmr2.py 算 Authenticode 和读 UKI 的 .cmdline |
| systemd-ukify  | 拼 UKI                                                   |

安装 mkosi 26 与 Go 1.26.1：

```bash
# mkosi 装进 venv，verify.sh 默认找 ~/mkosi-venv
python3 -m venv ~/mkosi-venv
~/mkosi-venv/bin/pip install mkosi==26

# Go 版本要跟被验那一行的 go_version 一致，对不上 verify.sh 直接停
curl -fL https://go.dev/dl/go1.26.1.linux-amd64.tar.gz | tar -C /usr/local -xz
export PATH=$PATH:/usr/local/go/bin
```

### zeroseal-verifier 与 verify.sh

接着 clone 本项目到 Linux 上，运行 `verify.sh`：

```bash
git clone https://github.com/Falicitas/zeroseal-verifier
cd zeroseal-verifier
./verify.sh            # 验最新发布的那一版
```

>   第一次跑要几十分钟，绝大部分时间在下包和 mkosi tools 树。将 mkosi tools 树固定并作为 release 分发的原因见后文「xxyy」。

### 输出结果

>   下文的「离线」指“不需要跟远端 TDX 服务器交互”，与「在线」“挑战 TDX，要求 TDX 生成实时证明”形成对照。「离线」的构建过程是要联网的。

下面是一个输出的结构（已省略哈希）：

```
=== 验证 v0.2.1（发布于 ...）===
=== [0/5] 准备 tools 树 ===
tools: 694bd6ba… ✓
=== [1/5] 从源码编译 gateway ===
gateway: … ✓
=== [2/5] 复现 shim / grub / stub ===
shim: … ✓
grub: … ✓
stub: … ✓
=== [3/5] mkosi 复现构建 ===
roothash: … ✓
=== [4/5] 复现 UKI ===
UKI: … ✓
=== [5/5] 期望 RTMR ===
shim   …
grub   …
kernel …
RTMR1 = …
MokList        …  OK
MokListX       …  OK
MokListTrusted …  OK
LoadOptions    …  OK
initrd         …  OK
RTMR2 = …

上面五项全部为 OK，说明 v0.2.1 的声明是可复现的。
```

zeroseal 在发布后端服务时，会将那一版全部产物的哈希写进仓库根目录的 `measurements.jsonl`，一版占一行。`./verify.sh` 不带参数时默认取最后一行，`./verify.sh v0.2.1` 则取指定版本的一行。总而言之，`measurements.jsonl` 聚合了自 zeroseal 提供服务以来所有版本的静态产物的离线度量值（在线度量值挑战见后面章节「xsgreg」）。这些值作为 zeroseal 宣称的「声明值」，与你本地离线构建的「复现值」进行比较。

`[0/5]` 到 `[4/5]` 每步做同一件事：在你的机器上造出一类 Linux 系统所需的中间产物，计算哈希值，最后跟 `measurements.jsonl` 中的一行的对应字段做比较。相同打 ✓ 往下走，不同就当场停下，把「复现值」和「声明值」两个不同的值打印在终端上。

| 步骤  | 在你机器上造出的产物    | 比较的字段               |
| ----- | ------------------------ | ----------------------------- |
| [0/5] | 解压好的 mkosi tools 树  | `tools_sha256`                |
| [1/5] | 从源码编译的 gateway     | `gateway_sha256`              |
| [2/5] | shim、grub、stub         | `shim_sha256`、`grub_sha256`  |
| [3/5] | rootfs 的 erofs 与 verity | `roothash`                   |
| [4/5] | UKI                      | `uki_sha256`                  |

>   stub 没有自己的字段。它作为构建 UKI 的输入之一，`[4/5]` 对上就说明它是对的。

>   `[1/5]` 如果选择提供编好的二进制，零信任拓展不到人类可读的 go 语言项目。即零信任将退化为：你需要信任我们提供的二进制没有中转掺水。所以 gateway 二进制不进本仓库。`[1/5]` 是现场从 `gateway_repo` 的 `gateway_commit` clone 下来并完成 Go 编译的。

>   `MokList` 那五行末尾的 `OK`，是逐个事件跟 `rtmr2.py` 顶部一张实测表对照，只用来定位是哪一项对不上，不参与 `RTMR2` 的计算。

五个 ✓ 合起来可以说明一件事：zeroseal 声明的每样产物，你能从公开的源码和配方自己造出来，且逐字节一致。这一步全程在你自己机器上离线构建，验的是「它公开出来的这套东西能否本地造得出来」。

`[5/5]` 把前面造出来的产物按 TDX 规定的顺序算一遍，打印 `RTMR1` 和 `RTMR2`。两个值被拿去跟远端那台实时运行的机器签名报告里的对应值比。它们基于什么能够无信任证明远端在跑的内容和用户离线构建的内容是一致，见后文「xxyy」。

