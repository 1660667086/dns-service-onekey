#!/usr/bin/env bash
set -euo pipefail

CLIENTS_FILE="${CLIENTS_FILE:-/etc/dns-service/clients.allow}"
ALLOW_PORTS="${ALLOW_PORTS:-53,80,443}"
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
  local port="$2"
  if ! rule_exists INPUT -p "$proto" --dport "$port" -j "$CHAIN"; then
    iptables -I INPUT -p "$proto" --dport "$port" -j "$CHAIN"
  fi
}

main() {
  ensure_iptables
  mkdir -p "$(dirname "$CLIENTS_FILE")"
  touch "$CLIENTS_FILE"

  if ! iptables -L "$CHAIN" -n >/dev/null 2>&1; then
    iptables -N "$CHAIN"
  fi

  IFS=',' read -r -a ports <<<"$ALLOW_PORTS"
  for port in "${ports[@]}"; do
    port="${port//[[:space:]]/}"
    [ -z "$port" ] && continue
    ensure_jump_rule tcp "$port"
    if [ "$port" = "53" ]; then
      ensure_jump_rule udp "$port"
    fi
  done
  iptables -F "$CHAIN"

  iptables -A "$CHAIN" -s 127.0.0.1/32 -j ACCEPT

  while IFS= read -r client; do
    client="${client%%#*}"
    client="${client//[[:space:]]/}"
    [ -z "$client" ] && continue
    iptables -A "$CHAIN" -s "$client" -j ACCEPT
  done <"$CLIENTS_FILE"

  iptables -A "$CHAIN" -j DROP
  info "DNS 解锁客户端白名单已同步到 iptables，端口：$ALLOW_PORTS。"
}

main "$@"
