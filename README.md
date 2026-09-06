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

下面是一个输出的结构（已省略哈希值）：

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

zeroseal 在发布后端服务时，会将那一版全部产物的哈希值写进仓库根目录的 `measurements.jsonl`，一版占一行。`./verify.sh` 不带参数时默认取最后一行，`./verify.sh v0.2.1` 则取指定版本的一行。总而言之，`measurements.jsonl` 聚合了自 zeroseal 提供服务以来所有版本的静态产物的离线度量值（在线度量值挑战见后面章节「xsgreg」）。这些值作为 zeroseal 宣称的「声明值」，与你本地离线构建的「复现值」进行比较。

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

`[5/5]` 把前面造出来的产物按 TDX 规定的顺序算一遍，打印 `RTMR1` 和 `RTMR2`。两个值被拿去跟远端那台实时运行的机器签名报告里的对应值比。它们基于什么能够无信任证明远端在跑的内容和用户离线构建的内容是一致，见后文「远端如何证明自己在跑什么」。

### 远端如何证明自己在跑什么

要让远端声明自己在跑什么，最直接的办法是让它上面的程序生成报告，并暴露一个接口供人调用。但这份报告如果由那台机器的 OS 生成，那么能 ssh 到那台机器上的人将有能力换掉报告。报告和被报告的对象出自同一个可被运维人员篡改的机器上，它就不构成证据。

报告须来自 OS 管不到的地方 —— 比 OS 更早启动、且 OS 无权改写的地方。CPU 满足这个条件。

CPU 提供一组寄存器，并保证这组寄存器对软件只开放一个操作：

```
新值 = SHA384(旧值 ‖ 这次追加的内容)
```

即只做追加操作。没有写入接口，没有重置接口，回退不到上一个值。

往里追加的动作由软件自己做：OS 挂载的每一段代码在把控制权交给下一段之前，先把下一段的字节算成哈希值追加进去。固件度量 bootloader，bootloader 度量 kernel，...。

既然是软件自己往里写，被掉包的那一段代码为什么不能追加一个假哈希值？因为它要先拿到控制权才能执行，而给它控制权的是上一段代码 —— 上一段会先把它的真实字节度量进去。轮到它执行时，寄存器里已经写着它自己的哈希值。整条链的起点是 TD 建立那一刻由 TDX 模块算出的 `MRTD`，一路到覆盖 zeroseal 中转二进制服务的 RTMR2。

![tdx_trust_chain_zoom_lens](./README.assets/tdx_trust_chain_zoom_lens.svg)

>   TDX 模块本身的可信来源见下图
>
>   ![tdx_module_root_of_trust](./README.assets/tdx_module_root_of_trust.svg)

TDX 里这样的寄存器有四个，`RTMR0` 到 `RTMR3`。CPU 把它们连同 `MRTD` 和硬件身份放进一份数据结构，用一把出厂时经 Intel 认证的密钥签名。签过名的这份东西叫 quote，伪造它等于伪造 Intel 那条证书链。

>   quote 的签名验证是独立的一步，走标准的 Intel QVL 流程（PCK 证书链回溯到 Intel root CA），跟本仓库做的本地复现是两件事，见后文「xsgreg」。

到这里远端能对外暴露 quote 接口来证明「远端机器此时 CPU 寄存器是这几个值」。不过寄存器只有 48 字节，装的是哈希值，从 quote 看不出它跑的是什么内容。

这就有了 zeroseal-verifier 这个开源项目。zeroseal-verifier 把远端在跑的系统，在你自己机器上原样造一遍所有构建该系统所用的产物，按「同样的顺序、同样的规则」完成哈希值计算，再跟 quote 里的运维人员无法篡改的寄存器值进行比较，附带来自 Intel 的签名。`[0/5]` 到 `[4/5]` 制造产物，`[5/5]` 负责计算度量值。

>   「同样的顺序、同样的规则」：哪个阶段该度量什么、按什么编码、追加进哪个寄存器，由 UEFI 与 TCG 的规范规定；运行中的机器会把每一次追加按序记进一份事件日志，TDX 里这份日志由 ACPI 的 `CCEL` 表（Confidential Computing Event Log）指向。`[5/5]` 输出里 `MokList` 到 `initrd` 那五行，就是 RTMR2 对应的五条 CCEL 事件，`rtmr2.py` 按同一顺序把它们重放一遍。
>
>   事件日志本身跟 OS 一样能被改。它的作用只是提供度量事件；证据来源于用户独立度量得到的值能与 quote 里的寄存器值相等。

这点也说明用户使用的机器不需要有 TDX 能力的 CPU 芯片。Intel CPU 芯片仅作为一个防运维通过 ssh 篡改寄存器值的硬件（并对寄存器值的真实性作签名），对于系统的构建配方，以及顺序度量的配方等，都是可公开，也需要被公开，让用户在常规 Linux 环境就可完成复现。

这条推理闭合的前提是构建可复现 —— 同样的源码和配方，在任何机器、任何时间都编出逐字节相同的产物。这也是为什么 `mkosi.conf` 里固定了 `Snapshot=`，`measurements.jsonl` 里固定了 `go_version` 与 `tools_sha256`。

### RTMR1 与 RTMR2 度量了什么

`RTMR1` 度量了启动链上三个可执行文件：shim、grub、kernel。`rtmr1.py` 对它们各算一个哈希，从全零开始按这个顺序叠出 `RTMR1`。

>   这三个都是 UEFI 可执行文件（PE 格式），文件里自带一块放数字签名的区域，Secure Boot 使用它来验签。算哈希时跳过这块内容。UEFI 为此规定了一套叫 Authenticode 的算法：跳过 checksum 字段和证书表两处再算。`rtmr1.py` 用的是它。

| 文件   | 来源                                                    |
| ------ | ------------------------------------------------------- |
| shim   | `build-grub-shim.sh` 从 `shim-signed` 包里取出的 `.efi` |
| grub   | 同上，取自 `grub-efi-amd64-signed`                      |
| kernel | mkosi 装进 rootfs 的内核包里的 vmlinuz                  |

>   shim 和 grub 是 Canonical 签好名的二进制，本仓库不自己编译它们，仅从固定快照里取出来。快照日期固定在 `build-grub-shim.sh` 里，与 `mkosi.conf` 的 `Snapshot=` 保持一致。

`RTMR2` 度量了 bootloader 读到的配置和数据，五条事件按固定顺序追加：

| 事件             | 内容                                       |
| ---------------- | ------------------------------------------ |
| `MokList`        | shim 信任的证书列表，从 shim 自己的 `.vendor_cert` 段重建 |
| `MokListX`       | 吊销列表，未 enroll 过 MOK 时是固定的空占位 |
| `MokListTrusted` | 同上，固定值 `sha384(0x01)`                |
| `LoadOptions`    | kernel cmdline，转成 UTF-16-LE 后算哈希    |
| `initrd`         | initrd 文件的 sha384                       |

>   `Mok` 是 Machine Owner Key，shim 留给机器主人的口子：往 Secure Boot 的信任列表里加自己的证书，加这个动作叫 enroll。这台机器没做过 enroll，所以前三条是固定值。换成 enroll 过的机器，这三条会变，复现值跟着不同。

rootfs 有几百 MB，寄存器只有 48 字节。zeroseal 利用 dm-verity 把 rootfs 将底层数据块自下而上组织成一棵哈希树，树根为一个 32 字节的哈希值 `roothash`。对任何数据块进行修改一个字节，树根值都会变化。`roothash` 写入了被度量的 kernel cmdline。cmdline 再和 kernel、initrd 一起打包成一个 EFI 文件，即 UKI，是 `[4/5]` 复现的目标。`rtmr2.py` 从 UKI 里取出 cmdline，算成 `LoadOptions`。这条信任链在验证时，如果反过来看：

```
RTMR2 相等 → cmdline 相等 → roothash 相等 → rootfs 每一字节相等 → gateway 二进制相等
```

对照 `[0/5]` 到 `[5/5]` 就是：`[3/5]` 造出 rootfs 并得到 `roothash`，`[4/5]` 把它写进 cmdline 打入 UKI，`[5/5]` 从 UKI 里读回来算 `RTMR2`。

>   这条链在整个运行期都成立。cmdline 里带着 `systemd.verity_root_options=panic-on-corruption`，运行期间读到任何一个块跟哈希树对不上，内核当场 panic。

>   UKI 在 `RTMR2` 里只承担一个角色：装 cmdline。`rtmr2.py` 拿它只为读 `.cmdline` 段，不对整个 UKI 文件算哈希。

