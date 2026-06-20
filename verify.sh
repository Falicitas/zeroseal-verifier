#!/bin/bash
# verify.sh — verifier 唯一入口:复现 shim/grub + 镜像 + UKI → 算期望 RTMR1/RTMR2
set -e
cd "$(dirname "$0")"
DATA=/dev/disk/by-id/nvme-Alibaba_Cloud_Elastic_Block_Storage_2ze6szkj0e6s0hsl6w5b
HASH=/dev/disk/by-id/nvme-Alibaba_Cloud_Elastic_Block_Storage_2ze6szkj0e6s0hsl6w5c
STUB=/usr/lib/systemd/boot/efi/linuxx64.efi.stub

echo "=== [0/4] 解压 tools 树 ==="
if [ ! -d mkosi.tools ]; then
  tar xzf mkosi.tools.tar.gz
  echo "tools 解压完成"
else
  echo "tools 已存在,跳过"
fi

echo "=== [1/4] 复现 shim/grub ==="
./build-grub-shim.sh

echo "=== [2/4] mkosi 复现构建 ==="
( . ~/mkosi-venv/bin/activate && mkosi --force build 2>&1 | tail -3 )
RH=$(cat zeroseal.roothash); echo "roothash: $RH"

echo "=== [3/4] 复现 UKI ==="
CMDLINE="systemd.verity=1 roothash=$RH systemd.verity_root_data=$DATA systemd.verity_root_hash=$HASH systemd.verity_root_options=panic-on-corruption console=tty0 console=ttyS0,115200n8 net.ifnames=0 nvme_core.io_timeout=4294967295 iommu=pt"
ukify build --linux=zeroseal.vmlinuz --initrd=zeroseal.initrd --cmdline="$CMDLINE" --stub="$STUB" --output=zeroseal.efi >/dev/null
echo "UKI: $(sha256sum zeroseal.efi | cut -d' ' -f1)"

echo "=== [4/4] 期望 RTMR ==="
python3 rtmr1.py zeroseal-shimx64.efi zeroseal-grubx64.efi zeroseal.vmlinuz
python3 rtmr2.py zeroseal-shimx64.efi zeroseal.efi zeroseal.initrd
echo; echo "↑ RTMR1/RTMR2 与 prover 的 quote 比对(下一步 verify-quote 接验签 + 逐项)。"
