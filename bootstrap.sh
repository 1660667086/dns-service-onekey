#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/dns-service-onekey-src}"
BRANCH="${BRANCH:-main}"
REPO_URL="${REPO_URL:-}"
GITHUB_REPO="${GITHUB_REPO:-}"

info() {
  printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行，例如：curl -fsSL .../bootstrap.sh | sudo env GITHUB_REPO=你的用户名/dns-service-onekey bash"
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

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return
  fi

  local pm="$1"
  info "安装 git..."
  case "$pm" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates
      ;;
    dnf)
      dnf install -y git ca-certificates
      ;;
    yum)
      yum install -y git ca-certificates
      ;;
  esac
}

resolve_repo_url() {
  if [ -n "$REPO_URL" ]; then
    echo "$REPO_URL"
    return
  fi

  if [ -n "$GITHUB_REPO" ]; then
    echo "https://github.com/${GITHUB_REPO}.git"
    return
  fi

  die "缺少仓库地址。请设置 GITHUB_REPO=你的用户名/dns-service-onekey 或 REPO_URL=https://github.com/你的用户名/dns-service-onekey.git"
}

sync_repo() {
  local repo_url="$1"
  info "拉取仓库：$repo_url"
  if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" fetch --prune origin
    git -C "$INSTALL_DIR" checkout "$BRANCH"
    git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
  else
    rm -rf "$INSTALL_DIR"
    git clone --branch "$BRANCH" "$repo_url" "$INSTALL_DIR"
  fi
}

main() {
  require_root
  local pm repo_url
  pm="$(detect_package_manager)"
  ensure_git "$pm"
  repo_url="$(resolve_repo_url)"
  sync_repo "$repo_url"
  info "开始安装 DNS 服务..."
  bash "$INSTALL_DIR/install.sh"
}

main "$@"
