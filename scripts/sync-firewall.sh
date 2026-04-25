#!/usr/bin/env bash
set -euo pipefail

CLIENTS_FILE="${CLIENTS_FILE:-/etc/dns-service/clients.allow}"
DNS_PORT="${DNS_PORT:-53}"
CHAIN="DNS_SERVICE_ALLOW"

info() {
  printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*"
}

ensure_iptables() {
  command -v iptables >/dev/null 2>&1 || {
    warn "未找到 iptables，无法自动同步客户端白名单。请在云防火墙中限制 DNS 访问来源。"
    exit 0
  }
}

rule_exists() {
  iptables -C "$@" >/dev/null 2>&1
}

ensure_jump_rule() {
  local proto="$1"
  if ! rule_exists INPUT -p "$proto" --dport "$DNS_PORT" -j "$CHAIN"; then
    iptables -I INPUT -p "$proto" --dport "$DNS_PORT" -j "$CHAIN"
  fi
}

main() {
  ensure_iptables
  mkdir -p "$(dirname "$CLIENTS_FILE")"
  touch "$CLIENTS_FILE"

  if ! iptables -L "$CHAIN" -n >/dev/null 2>&1; then
    iptables -N "$CHAIN"
  fi

  ensure_jump_rule udp
  ensure_jump_rule tcp
  iptables -F "$CHAIN"

  iptables -A "$CHAIN" -s 127.0.0.1/32 -j ACCEPT

  while IFS= read -r client; do
    client="${client%%#*}"
    client="${client//[[:space:]]/}"
    [ -z "$client" ] && continue
    iptables -A "$CHAIN" -s "$client" -j ACCEPT
  done <"$CLIENTS_FILE"

  iptables -A "$CHAIN" -j DROP
  info "DNS 客户端白名单已同步到 iptables。"
}

main "$@"
