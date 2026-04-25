#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="dnsmasq"
ADMIN_SERVICE_NAME="dns-service-admin"
CONFIG_DIR="/etc/dns-service"
DNSMASQ_CONFIG="/etc/dnsmasq.d/github-dns-service.conf"
ADMIN_APP_DIR="/opt/dns-service-onekey"
ADMIN_SERVICE_FILE="/etc/systemd/system/${ADMIN_SERVICE_NAME}.service"
CLIENTS_FILE="$CONFIG_DIR/clients.allow"
FIREWALL_SYNC_SCRIPT="$ADMIN_APP_DIR/scripts/sync-firewall.sh"

LISTEN_ADDR="${LISTEN_ADDR:-127.0.0.1}"
DNS_PORT="${DNS_PORT:-53}"
UPSTREAM_DNS="${UPSTREAM_DNS:-1.1.1.1,8.8.8.8}"
CACHE_SIZE="${CACHE_SIZE:-10000}"
LOG_QUERIES="${LOG_QUERIES:-0}"
ADMIN_BIND="${ADMIN_BIND:-127.0.0.1}"
ADMIN_PORT="${ADMIN_PORT:-8080}"
CLIENT_ALLOWLIST="${CLIENT_ALLOWLIST:-}"
RAW_BASE="${RAW_BASE:-}"

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
  info "安装 dnsmasq、Python 与防火墙工具..."
  case "$pm" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq python3 iptables
      ;;
    dnf)
      dnf install -y dnsmasq python3 iptables
      ;;
    yum)
      yum install -y dnsmasq python3 iptables
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
  touch "$CLIENTS_FILE"
  chmod 0644 "$CONFIG_DIR/hosts"
  chmod 0644 "$CLIENTS_FILE"

  if [ -n "$CLIENT_ALLOWLIST" ]; then
    : >"$CLIENTS_FILE"
    IFS=',' read -r -a clients <<<"$CLIENT_ALLOWLIST"
    for client in "${clients[@]}"; do
      client="${client//[[:space:]]/}"
      [ -n "$client" ] && echo "$client" >>"$CLIENTS_FILE"
    done
  fi

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
  if [ -n "$CLIENT_ALLOWLIST" ] && [ -x "$FIREWALL_SYNC_SCRIPT" ]; then
    "$FIREWALL_SYNC_SCRIPT" || true
    return
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
    if [ -n "$CLIENT_ALLOWLIST" ]; then
      info "按客户端白名单开放 ufw DNS 端口..."
      IFS=',' read -r -a clients <<<"$CLIENT_ALLOWLIST"
      for client in "${clients[@]}"; do
        client="${client//[[:space:]]/}"
        [ -z "$client" ] && continue
        ufw allow from "$client" to any port "$DNS_PORT" proto udp || true
        ufw allow from "$client" to any port "$DNS_PORT" proto tcp || true
      done
    else
      info "开放 ufw DNS 端口 $DNS_PORT/udp 与 $DNS_PORT/tcp..."
      ufw allow "$DNS_PORT/udp" || true
      ufw allow "$DNS_PORT/tcp" || true
    fi
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    if [ -n "$CLIENT_ALLOWLIST" ]; then
      info "按客户端白名单开放 firewalld DNS 端口..."
      IFS=',' read -r -a clients <<<"$CLIENT_ALLOWLIST"
      for client in "${clients[@]}"; do
        client="${client//[[:space:]]/}"
        [ -z "$client" ] && continue
        firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$client\" port protocol=\"udp\" port=\"$DNS_PORT\" accept" || true
        firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$client\" port protocol=\"tcp\" port=\"$DNS_PORT\" accept" || true
      done
    else
      info "开放 firewalld DNS 服务..."
      firewall-cmd --permanent --add-service=dns || true
    fi
    firewall-cmd --reload || true
  fi

  if [ -n "$CLIENT_ALLOWLIST" ] && ! command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1; then
    warn "已设置 CLIENT_ALLOWLIST，但未检测到 ufw 或 firewalld。请在云防火墙/系统防火墙中只允许这些客户端访问 $DNS_PORT 端口：$CLIENT_ALLOWLIST"
  fi
}

enable_service() {
  info "启动 dnsmasq..."
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

install_admin_panel() {
  info "安装 Web 管理面板..."
  install -d -m 0755 "$ADMIN_APP_DIR/web"
  install -d -m 0755 "$ADMIN_APP_DIR/scripts"

  local script_dir=""
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

  if [ -n "$script_dir" ] && [ -f "$script_dir/web/admin.py" ]; then
    install -m 0755 "$script_dir/web/admin.py" "$ADMIN_APP_DIR/web/admin.py"
    install -m 0755 "$script_dir/scripts/sync-firewall.sh" "$FIREWALL_SYNC_SCRIPT"
  elif [ -n "$RAW_BASE" ]; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$RAW_BASE/web/admin.py" -o "$ADMIN_APP_DIR/web/admin.py"
      curl -fsSL "$RAW_BASE/scripts/sync-firewall.sh" -o "$FIREWALL_SYNC_SCRIPT"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$ADMIN_APP_DIR/web/admin.py" "$RAW_BASE/web/admin.py"
      wget -qO "$FIREWALL_SYNC_SCRIPT" "$RAW_BASE/scripts/sync-firewall.sh"
    else
      warn "未找到 curl 或 wget，跳过 Web 面板安装。"
      return
    fi
    chmod 0755 "$ADMIN_APP_DIR/web/admin.py"
    chmod 0755 "$FIREWALL_SYNC_SCRIPT"
  else
    warn "未找到 web/admin.py。若使用 curl 管道安装，请设置 RAW_BASE，例如：sudo env RAW_BASE=https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main bash"
    return
  fi

  if [ ! -f "$CONFIG_DIR/admin.token" ]; then
    umask 077
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -base64 32 >"$CONFIG_DIR/admin.token"
    else
      date +%s%N | sha256sum | awk '{print $1}' >"$CONFIG_DIR/admin.token"
    fi
  fi

  cat >"$ADMIN_SERVICE_FILE" <<EOF
[Unit]
Description=DNS Service Web Admin
After=network-online.target dnsmasq.service
Wants=network-online.target

[Service]
Type=simple
Environment=DNS_HOSTS_FILE=$CONFIG_DIR/hosts
Environment=DNS_ADMIN_TOKEN_FILE=$CONFIG_DIR/admin.token
Environment=DNS_ADMIN_BIND=$ADMIN_BIND
Environment=DNS_ADMIN_PORT=$ADMIN_PORT
Environment=DNS_CLIENTS_FILE=$CLIENTS_FILE
Environment=DNS_FIREWALL_SYNC_CMD=$FIREWALL_SYNC_SCRIPT
ExecStart=/usr/bin/python3 $ADMIN_APP_DIR/web/admin.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$ADMIN_SERVICE_NAME"
  systemctl restart "$ADMIN_SERVICE_NAME"
  "$FIREWALL_SYNC_SCRIPT" || true
}

print_summary() {
  cat <<EOF

安装完成。

监听地址: $LISTEN_ADDR
监听端口: $DNS_PORT
上游 DNS: $UPSTREAM_DNS
客户端白名单: ${CLIENT_ALLOWLIST:-未设置}
主配置:   $DNSMASQ_CONFIG
自定义 hosts: $CONFIG_DIR/hosts
客户端白名单文件: $CLIENTS_FILE
Web 面板: http://$ADMIN_BIND:$ADMIN_PORT
管理 Token: $CONFIG_DIR/admin.token

常用命令:
  systemctl status dnsmasq
  systemctl status dns-service-admin
  journalctl -u dnsmasq -f
  journalctl -u dns-service-admin -f
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
  install_admin_panel
  print_summary
}

main "$@"
