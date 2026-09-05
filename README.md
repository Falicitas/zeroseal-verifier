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
- （必须）root。mkosi 要组 rootfs，而 Ubuntu 24.04 默认关掉了非特权 user namespace
  （`kernel.apparmor_restrict_unprivileged_userns=1`）

