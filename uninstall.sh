#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/etc/dns-service"
DNSMASQ_CONFIG="/etc/dnsmasq.d/github-dns-service.conf"
ADMIN_APP_DIR="/opt/dns-service-onekey"
ADMIN_SERVICE_FILE="/etc/systemd/system/dns-service-admin.service"
FIREWALL_CHAIN="DNS_SERVICE_ALLOW"

if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 运行：sudo bash uninstall.sh" >&2
  exit 1
fi

systemctl disable --now dnsmasq 2>/dev/null || true
systemctl disable --now dns-service-admin 2>/dev/null || true
rm -f "$DNSMASQ_CONFIG"
rm -f "$ADMIN_SERVICE_FILE"
if command -v iptables >/dev/null 2>&1; then
  iptables -D INPUT -p udp --dport 53 -j "$FIREWALL_CHAIN" 2>/dev/null || true
  iptables -D INPUT -p tcp --dport 53 -j "$FIREWALL_CHAIN" 2>/dev/null || true
  iptables -F "$FIREWALL_CHAIN" 2>/dev/null || true
  iptables -X "$FIREWALL_CHAIN" 2>/dev/null || true
fi
systemctl daemon-reload 2>/dev/null || true

if [ "${REMOVE_DATA:-0}" = "1" ]; then
  rm -rf "$CONFIG_DIR"
  rm -rf "$ADMIN_APP_DIR"
else
  echo "已保留 $CONFIG_DIR。若要删除数据，请运行：REMOVE_DATA=1 sudo bash uninstall.sh"
fi

echo "卸载完成。"
