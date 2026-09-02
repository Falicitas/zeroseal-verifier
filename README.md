# zeroseal-verifier

ZeroSeal 的 TDX 远程证明验证器 / A verifier for ZeroSeal's TDX remote attestation.

[中文](#中文) · [English](#english)

---

## 中文

### 这是什么

这个仓库包含一个 shell 脚本与脚本所用的一切配方，旨在让验证方在不需要信任，即零信任下确认 zeroseal 提供的中转服务正在运行的是[这套程序（以下简称 RPg）](https://github.com/Falicitas/zeroseal-gateway)，以及确认运行程序的完整 Linux OS。在你的 Linux 环境下运行 `./verify.sh`，将生成一个崭新的未挂载的 Linux OS，这个 OS 涵盖 RPg。最后我们利用可信执行环境（TEE）的能力，在零信任下让验证方确认 zeroseal 目前对外提供的服务的运行中的 OS 正是验证方自己独立手动生成的 OS。

注：你的 Linux 环境不需要使用 TDX 硬件，具体推荐环境如下：

- Ubuntu 24.04 LTS（noble）、x86_64。被验的镜像本身就是 noble，宿主同版本最省事
- 全新的云实例或干净容器。已有环境也能跑，只是 PATH 里若有自己编的 mkosi 或 ukify
  会被优先取用，那会算出不一样的结果
- 20 GB 空闲磁盘。tools 树解开 1.3 GB，mkosi 产出的 rootfs、erofs、verity 合计约
  2 GB，Go 工具链与编译缓存再占 1 GB
- 2 vCPU / 4 GB 内存
- 能连外网：Ubuntu 官方源与 snapshot 服务、GitHub、Go module proxy
- root。mkosi 要组 rootfs，而 Ubuntu 24.04 默认关掉了非特权 user namespace
  （`kernel.apparmor_restrict_unprivileged_userns=1`），用 root 最省事

### 验证什么

RTMR1：shim、grub、kernel 三个 PE 的 Authenticode 度量（SHA384），按 RTMR extend 规则依次算进去。

RTMR2：五个 CCEL 事件依次 extend ——

- MokList → 从 shim 的 `.vendor_cert` 重建
- MokListX / MokListTrusted → MOK 未 enroll 时的固定默认值
- LoadOptions → cmdline 转 UTF-16-LE
- initrd → initrd 文件的 sha384

两条都从公开的 mkosi 配方 + 构建脚本 + `rtmr1.py` / `rtmr2.py` 算出来。

### 不验证什么

MRTD 和 RTMR0。MRTD 要拿 TDVF 固件（`.fd`）按页重算，RTMR0 测的是固件配置和 TDVF 内部数据，都在 `.fd` 里。阿里云不提供 `.fd`，这两个值的参考只能来自阿里云的远程证明服务（appraisal），或者从一台已知干净的实例 pin 下来。

`measurements.jsonl` 里记了这两个值，但那是部署当时从 quote 里读到的，谁都重算不出来。

谁证明什么：Intel 签名链证明这是真 TDX 硬件、TCB 最新，标准 Intel QVL 就能验；RTMR1/RTMR2 证明 rootfs 和启动链是声明的那个可复现构建。固件那层在 TCB 里。

### 怎么跑

前置：

```bash
sudo apt update
sudo apt install -y git jq curl python3-venv python3-pefile systemd-ukify systemd-boot-efi

# mkosi 装进 venv，verify.sh 默认找 ~/mkosi-venv
python3 -m venv ~/mkosi-venv
~/mkosi-venv/bin/pip install mkosi==<版本>

# Go 版本要跟被验那一行的 go_version 一致，对不上 verify.sh 直接停
curl -fL https://go.dev/dl/go1.26.1.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
export PATH=$PATH:/usr/local/go/bin
```

`veritysetup` 和 `mkfs.erofs` 不用装，在 tools 树里。

tools 树 `mkosi.tools.tar.gz`（330M）没进 git。自己从本仓库 Release 下好放到根目录，
或者直接跑 verify.sh，缺文件时它会问要不要替你下。两种都会按 `tools_sha256` 校验后
才解压。

```bash
./verify.sh            # 验最新发布的那一版
./verify.sh v0.2.0     # 验指定版本
```

版本来自 `measurements.jsonl`，一行一次发布，只追加。所以每次发布的 git diff
就是加一行，改既有行会在 diff 里露出来。

verify.sh 逐项重建，跟那一行声明的值比，对不上就退出：

| 步骤 | 比对什么 |
|---|---|
| 从源码编译 gateway | `gateway_sha256` |
| 复现 shim / grub | `shim_sha256` / `grub_sha256` |
| mkosi 复现构建 | `roothash` |
| 复现 UKI | `uki_sha256` |
| 算 RTMR1 / RTMR2 | 打印，留给下一步跟 quote 比 |

gateway 二进制不进这个仓库，由 verify.sh 从 `gateway_repo` 的 `gateway_commit`
现场编。放个二进制进来就等于让你信我们。

### 本部署常量

下面这些只对某一套特定 ZeroSeal 部署成立，换部署要改：

- 被验那一行里的全部字段——盘的 by-id 路径（进 cmdline，因而进 RTMR2）、
  gateway 的 commit 与期望 sha256、Go 版本、tools 树、各项期望度量值
- MOK 未 enroll（rtmr2.py 用全零 sha256 的 MokListX 和 `sha384(0x01)` 的 MokListTrusted；别的实例上 enroll 过 MOK，这两段会变）
- stub 版本（systemd-ukify 的 `linuxx64.efi.stub`，版本不同 UKI 不一致）

clone 下来直接跑、RTMR 跟某个 quote 对不上，先核对这三项，再怀疑 quote。

### 仓库文件

- `mkosi.conf` / `mkosi.postinst.chroot` / `mkosi.postoutput` — mkosi 构建配方
- `mkosi.tools.manifest` — tools 树的包清单（`snapshot: null`，光靠它复现不出 bit-identical 的树，版本固定在树里，所以 tools 单独发）
- `measurements.jsonl` — 每次发布追加一行：gateway 的 repo/commit/期望 sha256、
  Go 版本与构建命令、tools 树的 URL 与哈希、盘的 by-id 路径、期望的
  roothash/UKI/shim/grub，以及部署当时读到的 MRTD 与 RTMR0-3。
  verify.sh 全部从这里读
- `overlay/` — rootfs overlay，跟实际部署逐字节一致。镜像里没有 sshd，所以没有
  不能公开的东西；唯一不在这里的是 gateway 二进制，由 verify.sh 编
- `build-grub-shim.sh` — 复现 shim/grub
- `verify.sh` — 验证入口
- `rtmr1.py` / `rtmr2.py` — RTMR1 / RTMR2 重算脚本

### TODO

- verify-quote：Intel 签名链验证（PCK 证书链 → Intel root CA）+ RTMR 逐项比对。MRTD/RTMR0 怎么处理（信阿里云 appraisal 还是 pin 参考实例）在这一步定。

---

## English

Given the prover's quote, recompute the expected RTMR1 and RTMR2 from public materials on an ordinary (non-TDX) Linux machine and compare them byte-for-byte against the quote. No TDX hardware needed.

### What it verifies

RTMR1: Authenticode PE measurements (SHA384) of shim, grub, and kernel, extended into RTMR1 in order.

RTMR2: five CCEL events extended in sequence —

- MokList → rebuilt from shim's `.vendor_cert`
- MokListX / MokListTrusted → fixed defaults for an un-enrolled MOK state
- LoadOptions → cmdline encoded as UTF-16-LE
- initrd → sha384 of the initrd file

Both are computed from the public mkosi recipe, the build scripts, and `rtmr1.py` / `rtmr2.py`.

### What it does not verify

MRTD and RTMR0 cannot be reproduced. MRTD requires the TDVF firmware (`.fd`) to recompute page by page; RTMR0 measures firmware configuration and TDVF internal data, both inside the `.fd`. Alibaba Cloud does not release the `.fd`, so the reference for these two values can only come from Alibaba's attestation (appraisal) service, or be pinned from a known-clean reference instance. They are out of scope for this offline verifier.

`measurements.jsonl` still records these two, but they are values observed in the quote at
deploy time, not conclusions anyone can recompute — a different kind of claim from
RTMR1/RTMR2, and not to be conflated with them.

How the trust decision splits: the Intel signature chain proves genuine TDX hardware with an up-to-date TCB (the standard Intel QVL checks this), and RTMR1/RTMR2 prove the rootfs and boot chain match the declared reproducible build. The firmware layer (MRTD/RTMR0) sits in the TCB.

### How to run

Prerequisites:

- a venv with mkosi installed, expected at `~/mkosi-venv`
- `systemd-ukify` (verify.sh uses its stub)
- `git`, `jq`, and the exact Go version named in the row under verification (a different compiler
  yields a different binary and therefore a different roothash; verify.sh checks first)
- the tools tree `mkosi.tools.tar.gz` (330M, not in git). Either download it from this repo's
  Release and drop it in the repo root, or just run verify.sh — it offers to fetch it when
  missing. Either way it is checked against `tools_sha256` before extraction

```bash
./verify.sh            # verify the most recent release
./verify.sh v0.2.0     # verify a specific version
```

The release under verification comes from `measurements.jsonl` — one line per release,
append-only, existing lines are never edited. It doubles as the public record: the git
diff of a release is exactly one added line, so any edit to an existing line is visible.

verify.sh rebuilds each artifact and compares it against that line, exiting on the first
mismatch:

| step | compared against |
|---|---|
| build gateway from source | `gateway_sha256` |
| reproduce shim / grub | `shim_sha256` / `grub_sha256` |
| reproduce the image with mkosi | `roothash` |
| reproduce the UKI | `uki_sha256` |
| compute RTMR1 / RTMR2 | printed, for comparison against the quote |

The gateway binary is **not in this repository**. verify.sh compiles it on the spot from
`gateway_commit` in `gateway_repo`. Shipping the binary would ask you to trust us, and the
whole point here is that you do not have to.

### Per-deployment constants

This verifier reproduces expected values for one specific ZeroSeal deployment only. The following are hardcoded per-deployment constants and must change for a different deployment:

- every field of the row under verification — the disk by-id paths (they go into the
  cmdline and therefore into RTMR2), the gateway commit and expected sha256, the Go
  version, the tools tree, and the expected measurements
- MOK un-enrolled (rtmr2.py uses an all-zero sha256 MokListX and `sha384(0x01)` MokListTrusted; both change if MOK is enrolled on another instance)
- the stub version (systemd-ukify's `linuxx64.efi.stub`; a different version yields a different UKI)

If a clone produces RTMRs that do not match a given quote, check these three for alignment before concluding the quote is at fault.

### Repository layout

- `mkosi.conf` / `mkosi.postinst.chroot` / `mkosi.postoutput` — mkosi build recipe
- `mkosi.tools.manifest` — package list for the tools tree (`snapshot: null`; this alone is not bit-reproducible, the actual versions are pinned inside the tools tree, which is why the tree ships separately)
- `measurements.jsonl` — one line appended per release: the gateway repo/commit/expected
  sha256, Go version and build command, the tools tree URL and hash, the disk by-id paths,
  the expected roothash/UKI/shim/grub, and the MRTD and RTMR0-3 observed at deploy time.
  verify.sh reads everything from here
- `overlay/` — rootfs overlay, byte-identical to the deployed one. The image no longer
  ships sshd, so nothing in it is unpublishable; the only thing missing is the gateway
  binary, which verify.sh builds
- `build-grub-shim.sh` — reproduce shim/grub
- `verify.sh` — verifier entrypoint
- `rtmr1.py` / `rtmr2.py` — RTMR1 / RTMR2 recomputation

### TODO

- verify-quote: Intel signature chain verification (PCK cert chain → Intel root CA) plus per-RTMR comparison. The MRTD/RTMR0 handling (trust Alibaba's appraisal vs pin from a reference instance) is decided at this step.
