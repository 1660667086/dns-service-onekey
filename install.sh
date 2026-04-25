#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="dnsmasq"
CONFIG_DIR="/etc/dns-service"
DNSMASQ_CONFIG="/etc/dnsmasq.d/github-dns-service.conf"

LISTEN_ADDR="${LISTEN_ADDR:-127.0.0.1}"
DNS_PORT="${DNS_PORT:-53}"
UPSTREAM_DNS="${UPSTREAM_DNS:-1.1.1.1,8.8.8.8}"
CACHE_SIZE="${CACHE_SIZE:-10000}"
LOG_QUERIES="${LOG_QUERIES:-0}"

info() {
  printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行：sudo bash install.sh"
  fi
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    die "暂不支持当前系统：需要 apt、dnf 或 yum"
  fi
}

install_dnsmasq() {
  local pm="$1"
  info "安装 dnsmasq..."
  case "$pm" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq
      ;;
    dnf)
      dnf install -y dnsmasq
      ;;
    yum)
      yum install -y dnsmasq
      ;;
  esac
}

stop_local_resolved_if_needed() {
  if [ "$LISTEN_ADDR" != "127.0.0.1" ] && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
      warn "检测到 systemd-resolved 可能占用 53 端口，正在关闭本机 stub resolver..."
      mkdir -p /etc/systemd/resolved.conf.d
      cat >/etc/systemd/resolved.conf.d/no-stub-listener.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF
      systemctl restart systemd-resolved || true
    fi
  fi
}

write_dns_service_files() {
  info "写入 DNS 服务配置..."
  install -d -m 0755 /etc/dnsmasq.d
  install -d -m 0755 "$CONFIG_DIR/conf.d"
  touch "$CONFIG_DIR/hosts"
  chmod 0644 "$CONFIG_DIR/hosts"

  {
    echo "# Managed by dns-service-onekey"
    echo "port=$DNS_PORT"
    echo "listen-address=$LISTEN_ADDR"
    echo "bind-dynamic"
    echo "no-resolv"
    echo "domain-needed"
    echo "bogus-priv"
    echo "cache-size=$CACHE_SIZE"
    echo "addn-hosts=$CONFIG_DIR/hosts"
    echo "conf-dir=$CONFIG_DIR/conf.d,*.conf"
    IFS=',' read -r -a upstreams <<<"$UPSTREAM_DNS"
    for dns in "${upstreams[@]}"; do
      dns="${dns//[[:space:]]/}"
      [ -n "$dns" ] && echo "server=$dns"
    done
    if [ "$LOG_QUERIES" = "1" ]; then
      echo "log-queries"
      echo "log-facility=/var/log/dnsmasq.log"
    fi
  } >"$DNSMASQ_CONFIG"
}

open_firewall_if_available() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
    info "开放 ufw DNS 端口 $DNS_PORT/udp 与 $DNS_PORT/tcp..."
    ufw allow "$DNS_PORT/udp" || true
    ufw allow "$DNS_PORT/tcp" || true
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    info "开放 firewalld DNS 服务..."
    firewall-cmd --permanent --add-service=dns || true
    firewall-cmd --reload || true
  fi
}

enable_service() {
  info "启动 dnsmasq..."
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

print_summary() {
  cat <<EOF

安装完成。

监听地址: $LISTEN_ADDR
监听端口: $DNS_PORT
上游 DNS: $UPSTREAM_DNS
主配置:   $DNSMASQ_CONFIG
自定义 hosts: $CONFIG_DIR/hosts

常用命令:
  systemctl status dnsmasq
  journalctl -u dnsmasq -f
  dig @$LISTEN_ADDR example.com -p $DNS_PORT

添加自定义解析:
  echo "1.2.3.4 example.test" >> $CONFIG_DIR/hosts
  systemctl restart dnsmasq

EOF
}

main() {
  require_root
  local pm
  pm="$(detect_package_manager)"
  stop_local_resolved_if_needed
  write_dns_service_files
  install_dnsmasq "$pm"
  open_firewall_if_available
  enable_service
  print_summary
}

main "$@"
