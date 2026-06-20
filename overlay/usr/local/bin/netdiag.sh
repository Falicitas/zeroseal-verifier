#!/bin/bash
DIAGDISK=/dev/disk/by-id/nvme-Alibaba_Cloud_Elastic_Block_Storage_2ze6szkj0e6s0hsl6w5d

collect() {
  echo "########## NETDIAG START ##########"
  echo "===== uptime ====="
  uptime
  echo "===== eth0 状态 ====="
  ip addr show eth0 2>&1
  cat /sys/class/net/eth0/operstate 2>&1
  echo "===== ip route ====="
  ip route 2>&1
  echo "===== netif links 状态(看 ADMIN_STATE / IPV4_ADDRESS_STATE)====="
  cat /run/systemd/netif/links/* 2>&1
  echo "===== netif leases(有 IPv4 lease 就有内容)====="
  cat /run/systemd/netif/leases/* 2>&1
  echo "===== networkd 完整日志(重点看 eth0 / DHCPv4 / Configuring)====="
  journalctl -u systemd-networkd --no-pager 2>&1
  echo "===== ss 监听 ====="
  ss -tlnp 2>&1
  echo "########## NETDIAG END ##########"
}

OUT=$(collect 2>&1)
if [ -b "$DIAGDISK" ]; then
  echo "$OUT" | dd of="$DIAGDISK" bs=1M conv=fsync 2>/dev/null
fi
echo "$OUT" > /dev/console 2>&1
