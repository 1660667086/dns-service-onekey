#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/etc/dns-service"
DNSMASQ_CONFIG="/etc/dnsmasq.d/github-dns-service.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 运行：sudo bash uninstall.sh" >&2
  exit 1
fi

systemctl disable --now dnsmasq 2>/dev/null || true
rm -f "$DNSMASQ_CONFIG"

if [ "${REMOVE_DATA:-0}" = "1" ]; then
  rm -rf "$CONFIG_DIR"
else
  echo "已保留 $CONFIG_DIR。若要删除数据，请运行：REMOVE_DATA=1 sudo bash uninstall.sh"
fi

echo "卸载完成。"
