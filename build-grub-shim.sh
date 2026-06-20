#!/bin/bash
# build-grub-shim.sh — 用与生产同一 Snapshot 的 mkosi 抽出 shim/grub 签名件
# 产物(deploy 当 bootloader、verify 当原材料): ./zeroseal-shimx64.efi  ./zeroseal-grubx64.efi
set -e
cd "$(dirname "$0")"
SNAPSHOT=20260430T230000Z          # 必须与生产 mkosi.conf 的 Snapshot 完全一致
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/mkosi.conf" << EOF
[Distribution]
Distribution=ubuntu
Release=noble
Architecture=x86-64
Snapshot=$SNAPSHOT

[Content]
Packages=
  shim-signed
  grub-efi-amd64-signed

[Output]
Format=directory
Output=tree
EOF

( . ~/mkosi-venv/bin/activate && cd "$WORK" && mkosi --force build 2>&1 | tail -3 )

cp "$WORK/tree/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" ./zeroseal-grubx64.efi
for c in shimx64.efi.signed.latest shimx64.efi.signed shimx64.efi.dualsigned; do
  [ -f "$WORK/tree/usr/lib/shim/$c" ] && { cp "$WORK/tree/usr/lib/shim/$c" ./zeroseal-shimx64.efi; break; }
done
echo "=== 产物 ==="; sha256sum ./zeroseal-shimx64.efi ./zeroseal-grubx64.efi
