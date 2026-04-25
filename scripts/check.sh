#!/usr/bin/env bash
set -euo pipefail

DNS_SERVER="${DNS_SERVER:-127.0.0.1}"
DNS_PORT="${DNS_PORT:-53}"
DOMAIN="${DOMAIN:-example.com}"

if ! command -v dig >/dev/null 2>&1; then
  echo "缺少 dig，请先安装 dnsutils 或 bind-utils。" >&2
  exit 1
fi

dig "@$DNS_SERVER" "$DOMAIN" -p "$DNS_PORT" +short
