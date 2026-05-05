#!/usr/bin/env bash
set -euo pipefail

ADMIN_SERVICE_NAME="dns-service-admin"
CONFIG_DIR="/etc/dns-service"
ADMIN_APP_DIR="/opt/dns-service-onekey"
ADMIN_SERVICE_FILE="/etc/systemd/system/${ADMIN_SERVICE_NAME}.service"
CLIENTS_FILE="$CONFIG_DIR/clients.allow"
FIREWALL_SYNC_SCRIPT="$ADMIN_APP_DIR/scripts/sync-firewall.sh"
CORE_INSTALLER_URL="${CORE_INSTALLER_URL:-}"
RAW_BASE="${RAW_BASE:-}"
ADMIN_BIND="${ADMIN_BIND:-0.0.0.0}"
ADMIN_PORT="${ADMIN_PORT:-8080}"
CLIENT_ALLOWLIST="${CLIENT_ALLOWLIST:-}"

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

download_file() {
  local url="$1"
  local output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$output" "$url"
  else
    die "未找到 curl 或 wget"
  fi
}

ensure_python3() {
  if command -v python3 >/dev/null 2>&1; then
    return
  fi

  info "安装 Web 面板运行所需 Python3..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y python3
  elif command -v yum >/dev/null 2>&1; then
    yum install -y python3
  else
    die "未找到可用包管理器安装 python3"
  fi
}

port_53_listeners() {
  if command -v ss >/dev/null 2>&1; then
    ss -lntup 2>/dev/null | awk '$5 ~ /:53$/ {print}'
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntup 2>/dev/null | awk '$4 ~ /:53$/ {print}'
  fi
}

prepare_dns_port() {
  info "检查并释放 53 端口..."

  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
      warn "检测到 systemd-resolved，关闭 DNSStubListener 以释放 53 端口..."
      mkdir -p /etc/systemd/resolved.conf.d
      cat >/etc/systemd/resolved.conf.d/no-stub-listener.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF
      systemctl restart systemd-resolved || true
    fi
  fi

  for service in dnsmasq named bind9 unbound; do
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
      if systemctl is-active --quiet "$service" 2>/dev/null; then
        warn "停止已存在的 $service 服务，避免占用 53 端口..."
        systemctl stop "$service" || true
      fi
    fi
  done

  local listeners
  listeners="$(port_53_listeners || true)"
  if [ -n "$listeners" ]; then
    printf '%s\n' "$listeners" >&2
    die "53 端口仍被占用。请先停止上面显示的进程后重新安装。"
  fi
}

install_original_dns_unlock() {
  local installer="/tmp/dnsmasq_sniproxy.sh"
  local script_dir=""
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

  if [ -n "$script_dir" ] && [ -f "$script_dir/upstream/dnsmasq_sniproxy.sh" ]; then
    info "运行仓库内置原版 Dnsmasq + SNI Proxy 安装脚本..."
    install -m 0755 "$script_dir/upstream/dnsmasq_sniproxy.sh" "$installer"
    export DNS_SERVICE_ONEKEY_RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/1660667086/dns-service-onekey/main}"
  else
    local core_url="$CORE_INSTALLER_URL"
    if [ -z "$core_url" ] && [ -n "$RAW_BASE" ]; then
      core_url="$RAW_BASE/upstream/dnsmasq_sniproxy.sh"
    fi
    [ -n "$core_url" ] || die "未找到内置核心安装脚本。请使用 bootstrap.sh 安装，或设置 RAW_BASE/CORE_INSTALLER_URL。"
    info "从你的仓库下载内置原版 Dnsmasq + SNI Proxy 安装脚本..."
    download_file "$core_url" "$installer"
    export DNS_SERVICE_ONEKEY_RAW_BASE="${RAW_BASE:-${core_url%/upstream/dnsmasq_sniproxy.sh}}"
  fi
  chmod +x "$installer"
  bash "$installer" -f
}

write_initial_clients() {
  install -d -m 0755 "$CONFIG_DIR"
  touch "$CLIENTS_FILE"
  chmod 0644 "$CLIENTS_FILE"

  if [ -n "$CLIENT_ALLOWLIST" ]; then
    : >"$CLIENTS_FILE"
    IFS=',' read -r -a clients <<<"$CLIENT_ALLOWLIST"
    for client in "${clients[@]}"; do
      client="${client//[[:space:]]/}"
      [ -n "$client" ] && echo "$client" >>"$CLIENTS_FILE"
    done
  fi
}

install_admin_panel() {
  info "安装 Web 允许 IP 管理面板..."
  install -d -m 0755 "$ADMIN_APP_DIR/web"
  install -d -m 0755 "$ADMIN_APP_DIR/scripts"

  local script_dir=""
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

  if [ -n "$script_dir" ] && [ -f "$script_dir/web/admin.py" ]; then
    install -m 0755 "$script_dir/web/admin.py" "$ADMIN_APP_DIR/web/admin.py"
    install -m 0755 "$script_dir/scripts/sync-firewall.sh" "$FIREWALL_SYNC_SCRIPT"
  elif [ -n "$RAW_BASE" ]; then
    download_file "$RAW_BASE/web/admin.py" "$ADMIN_APP_DIR/web/admin.py"
    download_file "$RAW_BASE/scripts/sync-firewall.sh" "$FIREWALL_SYNC_SCRIPT"
    chmod 0755 "$ADMIN_APP_DIR/web/admin.py" "$FIREWALL_SYNC_SCRIPT"
  else
    warn "未找到 web/admin.py。若使用 curl 管道安装，请设置 RAW_BASE。"
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
Description=DNS Unlock Web Allowlist Admin
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=DNS_RECORDS_FILE=/etc/dnsmasq.d/custom_netflix.conf
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
}

print_summary() {
  cat <<EOF

安装完成。

核心项目: 原版 dnsmasq_sniproxy_install
DNS 配置: /etc/dnsmasq.d/custom_netflix.conf
SNI 配置: /etc/sniproxy.conf
允许 IP: $CLIENTS_FILE
Web 面板: http://服务器IP:$ADMIN_PORT
管理 Token: $CONFIG_DIR/admin.token

常用命令:
  systemctl status dnsmasq
  systemctl status sniproxy
  systemctl status dns-service-admin
  journalctl -u dnsmasq -f
  journalctl -u sniproxy -f
  journalctl -u dns-service-admin -f

EOF
}

main() {
  require_root
  prepare_dns_port
  install_original_dns_unlock
  ensure_python3
  write_initial_clients
  install_admin_panel
  "$FIREWALL_SYNC_SCRIPT" || true
  print_summary
}

main "$@"
