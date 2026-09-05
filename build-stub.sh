#!/bin/bash
# build-stub.sh — 用与生产同一 Snapshot 的 mkosi 抽出 UKI 的 stub
# 产物(deploy 打 UKI、verify 复现 UKI 都用它): ./zeroseal-linuxx64.efi.stub
#
# 以前 deploy.sh 和 verify.sh 都直接读宿主机的
# /usr/lib/systemd/boot/efi/linuxx64.efi.stub。那份会随 apt 升级悄悄变 ——
# 2026-09-01 systemd-boot-efi 从 8.16 升到 8.17，当天前后打出的 UKI 就不是同一个。
# 而且第三方验证者宿主机的 systemd 版本跟我们不同就必然对不上，那不是他的错。
# stub 的字节是原样进 UKI 的，所以它必须跟 shim/grub 一样从 snapshot 里抽。
set -e
cd "$(dirname "$0")"
SNAPSHOT=20260901T000000Z          # 必须与生产 mkosi.conf 的 Snapshot 完全一致
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# systemd-boot-efi 在 universe，而 shim/grub 在 main。mkosi 默认只开 main，
# 不写这一行会报 Unable to locate package。
cat > "$WORK/mkosi.conf" << EOF
[Distribution]
Distribution=ubuntu
Release=noble
Architecture=x86-64
Repositories=main,universe
Snapshot=$SNAPSHOT

[Content]
Packages=
  systemd-boot-efi

[Output]
Format=directory
Output=tree
EOF

( . ~/mkosi-venv/bin/activate && cd "$WORK" && mkosi --force build 2>&1 | tail -3 )

cp "$WORK/tree/usr/lib/systemd/boot/efi/linuxx64.efi.stub" ./zeroseal-linuxx64.efi.stub
echo "=== 产物 ==="; sha256sum ./zeroseal-linuxx64.efi.stub
