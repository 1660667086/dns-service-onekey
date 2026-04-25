#!/usr/bin/env bash
set -euo pipefail

DNS_SERVER="${DNS_SERVER:-}"
INTERFACE="${INTERFACE:-}"

info() {
  printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行：sudo env DNS_SERVER=你的DNS服务器IP bash client-set-dns.sh"
  fi
}

detect_interface() {
  if [ -n "$INTERFACE" ]; then
    echo "$INTERFACE"
    return
  fi
  ip route 2>/dev/null | awk '/default/ {print $5; exit}'
}

main() {
  require_root
  [ -n "$DNS_SERVER" ] || die "请设置 DNS_SERVER，例如：sudo env DNS_SERVER=1.2.3.4 bash client-set-dns.sh"

  local iface
  iface="$(detect_interface)"

  if command -v resolvectl >/dev/null 2>&1 && [ -n "$iface" ]; then
    info "使用 resolvectl 设置 $iface 的 DNS..."
    resolvectl dns "$iface" "$DNS_SERVER"
    resolvectl domain "$iface" "~."
    resolvectl flush-caches 2>/dev/null || true
    resolvectl status "$iface" || true
    exit 0
  fi

  if command -v nmcli >/dev/null 2>&1 && [ -n "$iface" ]; then
    local conn
    conn="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v dev="$iface" '$2 == dev {print $1; exit}')"
    if [ -n "$conn" ]; then
      info "使用 NetworkManager 设置 $conn 的 DNS..."
      nmcli con mod "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$DNS_SERVER"
      nmcli con up "$conn"
      exit 0
    fi
  fi

  info "直接写入 /etc/resolv.conf..."
  cp -f /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  printf 'nameserver %s\n' "$DNS_SERVER" >/etc/resolv.conf
}

main "$@"
