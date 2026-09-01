# zeroseal-verifier

ZeroSeal 的 TDX 远程证明验证器 / A verifier for ZeroSeal's TDX remote attestation.

[中文](#中文) · [English](#english)

---

## 中文

给定 prover 的 quote,在一台普通(非 TDX)Linux 机器上从公开材料重新算出期望的 RTMR1 和 RTMR2,跟 quote 里的值逐字节比对。不需要 TDX 硬件。

### 验证什么

RTMR1:shim、grub、kernel 三个 PE 的 Authenticode 度量(SHA384),按 RTMR extend 规则依次算进 RTMR1。

RTMR2:五个 CCEL 事件依次 extend——

- MokList → 从 shim 的 `.vendor_cert` 重建
- MokListX / MokListTrusted → MOK 未 enroll 时的固定默认值
- LoadOptions → cmdline 转 UTF-16-LE
- initrd → initrd 文件的 sha384

这两条都从公开的 mkosi 配方 + 构建脚本 + `rtmr1.py` / `rtmr2.py` 算出来。

### 不验证什么

MRTD 和 RTMR0 复现不了。MRTD 要拿 TDVF 固件(`.fd`)按页重算,RTMR0 测的是固件配置和 TDVF 内部数据,都在 `.fd` 里。阿里云不提供 `.fd`,这两个值的参考只能走阿里云的远程证明服务(appraisal),或者从一台已知干净的实例 pin 值下来。它们不在这个离线验证器的覆盖范围内。

信任决策的分工:Intel 签名链证明是真 TDX 硬件 + TCB 最新(标准 Intel QVL 能验),RTMR1/RTMR2 证明 rootfs 和启动链是声明的那个可复现构建。固件那层(MRTD/RTMR0)在 TCB 里。

### 怎么跑

前置:

- 一个装好 mkosi 的 venv,默认在 `~/mkosi-venv`
- `systemd-ukify`(verify.sh 用它的 stub)
- `git`、`jq`,以及 `release.json` 里 `go_version` 指定的那个 Go 版本(版本不同编出来的
  二进制就不同,roothash 跟着不同;verify.sh 会先检查再往下走)
- tools 树 `mkosi.tools.tar.gz`(330M,没进 git)。可以自己从本仓库 Release 下好放到根目录,
  也可以直接跑 verify.sh —— 缺文件时它会问一句要不要替你下。两种方式都会按
  `release.json` 里的 `tools_sha256` 校验之后才解压

```bash
# 从 Release 拿到 mkosi.tools.tar.gz 放好后
./verify.sh
```

verify.sh 逐项重建并跟 `release.json` 声明的值比对,任何一项对不上就退出:

| 步骤 | 比对什么 |
|---|---|
| 从源码编译 gateway | `gateway_sha256` |
| 复现 shim / grub | `shim_sha256` / `grub_sha256` |
| mkosi 复现构建 | `roothash` |
| 复现 UKI | `uki_sha256` |
| 算 RTMR1 / RTMR2 | 打印,留给下一步跟 quote 比 |

gateway 二进制**不进这个仓库**——它由 verify.sh 从 `gateway_repo` 的 `gateway_commit`
现场编译。二进制进了仓库就等于让人信我们,而这里的整件事是不必信。

### 本部署常量

这个验证器复现的期望值只对某一套特定 ZeroSeal 部署成立。以下是写死的部署常量,换部署要改:

- `release.json` 里的全部字段——盘的 by-id 路径(它们进 cmdline,因而进 RTMR2)、
  gateway 的 commit 与期望 sha256、Go 版本、各项期望度量值
- MOK 未 enroll(rtmr2.py 用全零 sha256 的 MokListX 和 `sha384(0x01)` 的 MokListTrusted;别的实例上 enroll 过 MOK,这两段会变)
- stub 版本(systemd-ukify 的 `linuxx64.efi.stub`,版本不同 UKI 不一致)

clone 下来直接跑、算出的 RTMR 跟某个 quote 对不上,先核对上面三个是否一致,再判断是不是 quote 的问题。

### 仓库文件

- `mkosi.conf` / `mkosi.postinst.chroot` / `mkosi.postoutput` — mkosi 构建配方
- `mkosi.tools.manifest` — tools 树的包清单(`snapshot: null`,光这份复现不出 bit-identical,实际版本固定在 tools 树里,所以 tools 要单独发)
- `release.json` — 被验的那一版:gateway 的 commit 与期望 sha256、Go 版本、
  期望的 roothash/UKI/shim/grub。verify.sh 全部从这里读
- `overlay/` — rootfs overlay,跟实际部署逐字节一致。镜像里已经没有 sshd,
  所以不再有不能公开的东西;唯一不在这里的是 gateway 二进制(由 verify.sh 编)
- `build-grub-shim.sh` — 复现 shim/grub
- `verify.sh` — 验证入口
- `rtmr1.py` / `rtmr2.py` — RTMR1 / RTMR2 重算脚本

### TODO

- verify-quote:Intel 签名链验证(PCK 证书链 → Intel root CA)+ RTMR 逐项比对。MRTD/RTMR0 的处理(信阿里云 appraisal 还是参考实例 pin 值)在这一步定。

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

How the trust decision splits: the Intel signature chain proves genuine TDX hardware with an up-to-date TCB (the standard Intel QVL checks this), and RTMR1/RTMR2 prove the rootfs and boot chain match the declared reproducible build. The firmware layer (MRTD/RTMR0) sits in the TCB.

### How to run

Prerequisites:

- a venv with mkosi installed, expected at `~/mkosi-venv`
- `systemd-ukify` (verify.sh uses its stub)
- `git`, `jq`, and the exact Go version named in `release.json` (a different compiler
  yields a different binary and therefore a different roothash; verify.sh checks first)
- the tools tree `mkosi.tools.tar.gz` (330M, not in git). Either download it from this repo's
  Release and drop it in the repo root, or just run verify.sh — it offers to fetch it when
  missing. Either way it is checked against `tools_sha256` in `release.json` before extraction

```bash
# after placing mkosi.tools.tar.gz from the Release page
./verify.sh
```

verify.sh rebuilds each artifact and compares it against the value declared in
`release.json`, exiting on the first mismatch:

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

- every field in `release.json` — the disk by-id paths (they go into the cmdline and
  therefore into RTMR2), the gateway commit and expected sha256, the Go version, and
  the expected measurements
- MOK un-enrolled (rtmr2.py uses an all-zero sha256 MokListX and `sha384(0x01)` MokListTrusted; both change if MOK is enrolled on another instance)
- the stub version (systemd-ukify's `linuxx64.efi.stub`; a different version yields a different UKI)

If a clone produces RTMRs that do not match a given quote, check these three for alignment before concluding the quote is at fault.

### Repository layout

- `mkosi.conf` / `mkosi.postinst.chroot` / `mkosi.postoutput` — mkosi build recipe
- `mkosi.tools.manifest` — package list for the tools tree (`snapshot: null`; this alone is not bit-reproducible, the actual versions are pinned inside the tools tree, which is why the tree ships separately)
- `release.json` — the release under verification: gateway commit and expected sha256,
  Go version, expected roothash/UKI/shim/grub. verify.sh reads everything from here
- `overlay/` — rootfs overlay, byte-identical to the deployed one. The image no longer
  ships sshd, so nothing in it is unpublishable; the only thing missing is the gateway
  binary, which verify.sh builds
- `build-grub-shim.sh` — reproduce shim/grub
- `verify.sh` — verifier entrypoint
- `rtmr1.py` / `rtmr2.py` — RTMR1 / RTMR2 recomputation

### TODO

- verify-quote: Intel signature chain verification (PCK cert chain → Intel root CA) plus per-RTMR comparison. The MRTD/RTMR0 handling (trust Alibaba's appraisal vs pin from a reference instance) is decided at this step.
