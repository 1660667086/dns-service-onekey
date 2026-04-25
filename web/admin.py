#!/usr/bin/env python3
import ipaddress
import json
import os
import re
import secrets
import subprocess
import tempfile
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


HOSTS_FILE = Path(os.environ.get("DNS_HOSTS_FILE", "/etc/dns-service/hosts"))
CLIENTS_FILE = Path(os.environ.get("DNS_CLIENTS_FILE", "/etc/dns-service/clients.allow"))
TOKEN_FILE = Path(os.environ.get("DNS_ADMIN_TOKEN_FILE", "/etc/dns-service/admin.token"))
BIND = os.environ.get("DNS_ADMIN_BIND", "127.0.0.1")
PORT = int(os.environ.get("DNS_ADMIN_PORT", "8080"))
RESTART_CMD = os.environ.get("DNS_RESTART_CMD", "systemctl restart dnsmasq")
FIREWALL_SYNC_CMD = os.environ.get("DNS_FIREWALL_SYNC_CMD", "/opt/dns-service-onekey/scripts/sync-firewall.sh")

HOST_RE = re.compile(
    r"^(?=.{1,253}$)([a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*"
    r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
)
LOCK = threading.Lock()


INDEX_HTML = r"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DNS 管理</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f6f7f9;
      --panel: #ffffff;
      --text: #20242a;
      --muted: #667085;
      --line: #d8dde6;
      --primary: #2563eb;
      --primary-dark: #1d4ed8;
      --danger: #dc2626;
      --ok: #138a43;
      --shadow: 0 10px 30px rgba(15, 23, 42, .08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--text);
    }
    header {
      border-bottom: 1px solid var(--line);
      background: var(--panel);
    }
    .wrap { width: min(1120px, calc(100% - 32px)); margin: 0 auto; }
    .topbar {
      min-height: 68px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    h1 { margin: 0; font-size: 22px; font-weight: 750; letter-spacing: 0; }
    main { padding: 24px 0 40px; }
    .tabs {
      display: flex;
      gap: 8px;
      margin-bottom: 16px;
      flex-wrap: wrap;
    }
    .tab {
      background: #fff;
      color: var(--text);
      border-color: var(--line);
    }
    .tab.active {
      background: var(--primary);
      color: #fff;
      border-color: var(--primary);
    }
    .toolbar {
      display: grid;
      grid-template-columns: 1fr 1fr 1.2fr auto;
      gap: 10px;
      align-items: end;
      padding: 16px;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
    }
    label { display: grid; gap: 6px; color: var(--muted); font-size: 13px; }
    input {
      width: 100%;
      height: 38px;
      padding: 8px 10px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: #fff;
      color: var(--text);
      font: inherit;
    }
    input:focus { outline: 2px solid rgba(37, 99, 235, .18); border-color: var(--primary); }
    button {
      height: 38px;
      border: 1px solid transparent;
      border-radius: 6px;
      padding: 0 13px;
      font: inherit;
      font-weight: 650;
      cursor: pointer;
      background: var(--primary);
      color: #fff;
      white-space: nowrap;
    }
    button:hover { background: var(--primary-dark); }
    button.secondary { background: #fff; color: var(--text); border-color: var(--line); }
    button.secondary:hover { background: #f1f4f8; }
    button.danger { background: #fff; color: var(--danger); border-color: #f0b8b8; }
    button.danger:hover { background: #fff4f4; }
    .panel {
      margin-top: 18px;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
      overflow: hidden;
    }
    .panel-head {
      min-height: 54px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      padding: 12px 16px;
      border-bottom: 1px solid var(--line);
    }
    .status { color: var(--muted); font-size: 14px; }
    .status strong { color: var(--ok); }
    table { width: 100%; border-collapse: collapse; table-layout: fixed; }
    th, td { padding: 12px 14px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: middle; }
    th { color: var(--muted); font-size: 13px; font-weight: 700; background: #fbfcfe; }
    td.actions { width: 170px; text-align: right; }
    .empty { padding: 36px 16px; color: var(--muted); text-align: center; }
    .login {
      width: min(420px, calc(100% - 32px));
      margin: 14vh auto 0;
      padding: 20px;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
      display: grid;
      gap: 14px;
    }
    .login h1 { font-size: 21px; }
    .hidden { display: none !important; }
    .section.hidden { display: none !important; }
    .toast {
      position: fixed;
      right: 18px;
      bottom: 18px;
      max-width: min(420px, calc(100% - 36px));
      padding: 12px 14px;
      background: #111827;
      color: #fff;
      border-radius: 8px;
      box-shadow: var(--shadow);
      opacity: 0;
      transform: translateY(8px);
      transition: .18s ease;
    }
    .toast.show { opacity: 1; transform: translateY(0); }
    @media (max-width: 820px) {
      .toolbar { grid-template-columns: 1fr; }
      .topbar, .panel-head { align-items: flex-start; flex-direction: column; }
      table, thead, tbody, tr, th, td { display: block; }
      thead { display: none; }
      tr { padding: 10px 12px; border-bottom: 1px solid var(--line); }
      td { border: 0; padding: 6px 0; }
      td.actions { width: auto; text-align: left; display: flex; gap: 8px; }
    }
  </style>
</head>
<body>
  <section id="loginView" class="login">
    <h1>DNS 管理登录</h1>
    <label>管理 Token
      <input id="tokenInput" type="password" autocomplete="current-password" placeholder="输入 /etc/dns-service/admin.token 中的 token">
    </label>
    <button id="loginBtn">登录</button>
  </section>

  <section id="appView" class="hidden">
    <header>
      <div class="wrap topbar">
        <h1>DNS 管理面板</h1>
        <button id="logoutBtn" class="secondary">退出</button>
      </div>
    </header>
    <main class="wrap">
      <nav class="tabs">
        <button class="tab active" id="recordsTab" type="button">解析记录</button>
        <button class="tab" id="clientsTab" type="button">允许 IP</button>
      </nav>

      <section id="recordsSection" class="section">
        <form id="recordForm" class="toolbar">
          <label>域名
            <input id="hostInput" required placeholder="nas.lan">
          </label>
          <label>IP 地址
            <input id="ipInput" required placeholder="10.0.0.10">
          </label>
          <label>备注
            <input id="commentInput" placeholder="NAS">
          </label>
          <button id="saveBtn" type="submit">添加</button>
        </form>

        <section class="panel">
          <div class="panel-head">
            <div class="status" id="statusText">读取中...</div>
            <button id="refreshBtn" class="secondary">刷新</button>
          </div>
          <div id="tableMount"></div>
        </section>
      </section>

      <section id="clientsSection" class="section hidden">
        <form id="clientForm" class="toolbar">
          <label>允许访问 DNS 的 IP
            <input id="clientInput" required placeholder="1.2.3.4 或 1.2.3.0/24">
          </label>
          <label>备注
            <input id="clientCommentInput" placeholder="server-a">
          </label>
          <span></span>
          <button id="clientSaveBtn" type="submit">添加</button>
        </form>

        <section class="panel">
          <div class="panel-head">
            <div class="status" id="clientStatusText">读取中...</div>
            <button id="clientRefreshBtn" class="secondary">刷新</button>
          </div>
          <div id="clientTableMount"></div>
        </section>
      </section>
    </main>
  </section>
  <div id="toast" class="toast"></div>

  <script>
    const $ = (id) => document.getElementById(id);
    let editingHost = null;
    let editingClient = null;

    function token() { return localStorage.getItem("dns_admin_token") || ""; }
    function toast(msg) {
      $("toast").textContent = msg;
      $("toast").classList.add("show");
      setTimeout(() => $("toast").classList.remove("show"), 2600);
    }
    async function api(path, options = {}) {
      const res = await fetch(path, {
        ...options,
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token()}`,
          ...(options.headers || {})
        }
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || `请求失败：${res.status}`);
      return data;
    }
    function showApp() {
      $("loginView").classList.add("hidden");
      $("appView").classList.remove("hidden");
      load();
    }
    function showLogin() {
      $("appView").classList.add("hidden");
      $("loginView").classList.remove("hidden");
    }
    async function load() {
      try {
        await Promise.all([loadRecords(), loadClients()]);
      } catch (err) {
        localStorage.removeItem("dns_admin_token");
        showLogin();
        toast(err.message);
      }
    }
    async function loadRecords() {
      const data = await api("/api/records");
      $("statusText").innerHTML = `<strong>${data.count}</strong> 条解析记录，保存后自动重启 dnsmasq`;
      render(data.records);
    }
    async function loadClients() {
      const data = await api("/api/clients");
      $("clientStatusText").innerHTML = `<strong>${data.count}</strong> 个允许 IP，保存后自动同步防火墙`;
      renderClients(data.clients);
    }
    function render(records) {
      if (!records.length) {
        $("tableMount").innerHTML = `<div class="empty">暂无解析记录</div>`;
        return;
      }
      $("tableMount").innerHTML = `
        <table>
          <thead><tr><th>域名</th><th>IP 地址</th><th>备注</th><th></th></tr></thead>
          <tbody>
            ${records.map(r => `
              <tr>
                <td>${escapeHtml(r.host)}</td>
                <td>${escapeHtml(r.ip)}</td>
                <td>${escapeHtml(r.comment || "")}</td>
                <td class="actions">
                  <button class="secondary" data-edit="${escapeHtml(r.host)}">编辑</button>
                  <button class="danger" data-delete="${escapeHtml(r.host)}">删除</button>
                </td>
              </tr>
            `).join("")}
          </tbody>
        </table>`;
      document.querySelectorAll("[data-edit]").forEach(btn => btn.onclick = () => {
        const row = records.find(r => r.host === btn.dataset.edit);
        editingHost = row.host;
        $("hostInput").value = row.host;
        $("ipInput").value = row.ip;
        $("commentInput").value = row.comment || "";
        $("saveBtn").textContent = "保存";
        $("hostInput").focus();
      });
      document.querySelectorAll("[data-delete]").forEach(btn => btn.onclick = async () => {
        if (!confirm(`删除 ${btn.dataset.delete} ?`)) return;
        await api(`/api/records/${encodeURIComponent(btn.dataset.delete)}`, { method: "DELETE" });
        toast("已删除并重启 DNS 服务");
        loadRecords();
      });
    }
    function renderClients(clients) {
      if (!clients.length) {
        $("clientTableMount").innerHTML = `<div class="empty">暂无允许 IP，外部服务器不能使用此 DNS</div>`;
        return;
      }
      $("clientTableMount").innerHTML = `
        <table>
          <thead><tr><th>允许 IP / 网段</th><th>备注</th><th></th></tr></thead>
          <tbody>
            ${clients.map(c => `
              <tr>
                <td>${escapeHtml(c.client)}</td>
                <td>${escapeHtml(c.comment || "")}</td>
                <td class="actions">
                  <button class="secondary" data-client-edit="${escapeHtml(c.client)}">编辑</button>
                  <button class="danger" data-client-delete="${escapeHtml(c.client)}">删除</button>
                </td>
              </tr>
            `).join("")}
          </tbody>
        </table>`;
      document.querySelectorAll("[data-client-edit]").forEach(btn => btn.onclick = () => {
        const row = clients.find(c => c.client === btn.dataset.clientEdit);
        editingClient = row.client;
        $("clientInput").value = row.client;
        $("clientCommentInput").value = row.comment || "";
        $("clientSaveBtn").textContent = "保存";
        $("clientInput").focus();
      });
      document.querySelectorAll("[data-client-delete]").forEach(btn => btn.onclick = async () => {
        if (!confirm(`移除 ${btn.dataset.clientDelete} ?`)) return;
        await api(`/api/clients/${encodeURIComponent(btn.dataset.clientDelete)}`, { method: "DELETE" });
        toast("已同步允许 IP");
        loadClients();
      });
    }
    function escapeHtml(text) {
      return String(text).replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
    }
    $("loginBtn").onclick = () => {
      localStorage.setItem("dns_admin_token", $("tokenInput").value.trim());
      showApp();
    };
    $("logoutBtn").onclick = () => {
      localStorage.removeItem("dns_admin_token");
      showLogin();
    };
    $("refreshBtn").onclick = load;
    $("clientRefreshBtn").onclick = loadClients;
    $("recordsTab").onclick = () => switchTab("records");
    $("clientsTab").onclick = () => switchTab("clients");
    function switchTab(name) {
      $("recordsSection").classList.toggle("hidden", name !== "records");
      $("clientsSection").classList.toggle("hidden", name !== "clients");
      $("recordsTab").classList.toggle("active", name === "records");
      $("clientsTab").classList.toggle("active", name === "clients");
    }
    $("recordForm").onsubmit = async (event) => {
      event.preventDefault();
      const body = JSON.stringify({
        host: $("hostInput").value.trim(),
        ip: $("ipInput").value.trim(),
        comment: $("commentInput").value.trim()
      });
      const path = editingHost ? `/api/records/${encodeURIComponent(editingHost)}` : "/api/records";
      const method = editingHost ? "PUT" : "POST";
      await api(path, { method, body });
      editingHost = null;
      $("recordForm").reset();
      $("saveBtn").textContent = "添加";
      toast("已保存并重启 DNS 服务");
      loadRecords();
    };
    $("clientForm").onsubmit = async (event) => {
      event.preventDefault();
      const body = JSON.stringify({
        client: $("clientInput").value.trim(),
        comment: $("clientCommentInput").value.trim()
      });
      const path = editingClient ? `/api/clients/${encodeURIComponent(editingClient)}` : "/api/clients";
      const method = editingClient ? "PUT" : "POST";
      await api(path, { method, body });
      editingClient = null;
      $("clientForm").reset();
      $("clientSaveBtn").textContent = "添加";
      toast("已同步允许 IP");
      loadClients();
    };
    if (token()) showApp(); else showLogin();
  </script>
</body>
</html>
"""


def ensure_token():
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not TOKEN_FILE.exists():
        TOKEN_FILE.write_text(secrets.token_urlsafe(32) + "\n", encoding="utf-8")
        TOKEN_FILE.chmod(0o600)
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def parse_hosts():
    HOSTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    HOSTS_FILE.touch(exist_ok=True)
    records = []
    for line in HOSTS_FILE.read_text(encoding="utf-8").splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#"):
            continue
        left, _, comment = raw.partition("#")
        parts = left.split()
        if len(parts) < 2:
            continue
        ip = parts[0]
        for host in parts[1:]:
            records.append({"ip": ip, "host": host, "comment": comment.strip()})
    return sorted(records, key=lambda item: item["host"])


def write_hosts(records):
    lines = ["# Managed by DNS Web Admin"]
    for record in sorted(records, key=lambda item: item["host"]):
        comment = f" # {record['comment']}" if record.get("comment") else ""
        lines.append(f"{record['ip']} {record['host']}{comment}")

    fd, tmp_name = tempfile.mkstemp(prefix=".hosts.", dir=str(HOSTS_FILE.parent), text=True)
    with os.fdopen(fd, "w", encoding="utf-8") as tmp:
        tmp.write("\n".join(lines) + "\n")
    os.replace(tmp_name, HOSTS_FILE)


def parse_clients():
    CLIENTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    CLIENTS_FILE.touch(exist_ok=True)
    clients = []
    for line in CLIENTS_FILE.read_text(encoding="utf-8").splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#"):
            continue
        left, _, comment = raw.partition("#")
        parts = left.split()
        if not parts:
            continue
        clients.append({"client": parts[0], "comment": comment.strip()})
    return sorted(clients, key=lambda item: item["client"])


def write_clients(clients):
    lines = ["# Managed by DNS Web Admin"]
    for client in sorted(clients, key=lambda item: item["client"]):
        comment = f" # {client['comment']}" if client.get("comment") else ""
        lines.append(f"{client['client']}{comment}")

    fd, tmp_name = tempfile.mkstemp(prefix=".clients.", dir=str(CLIENTS_FILE.parent), text=True)
    with os.fdopen(fd, "w", encoding="utf-8") as tmp:
        tmp.write("\n".join(lines) + "\n")
    os.replace(tmp_name, CLIENTS_FILE)


def validate_record(record):
    host = str(record.get("host", "")).strip().lower()
    ip = str(record.get("ip", "")).strip()
    comment = str(record.get("comment", "")).strip()
    if not HOST_RE.match(host):
        raise ValueError("域名格式不正确")
    try:
        ipaddress.ip_address(ip)
    except ValueError as exc:
        raise ValueError("IP 地址格式不正确") from exc
    if len(comment) > 120:
        raise ValueError("备注不能超过 120 个字符")
    return {"host": host, "ip": ip, "comment": comment}


def validate_client(record):
    client = str(record.get("client", "")).strip()
    comment = str(record.get("comment", "")).strip()
    try:
        if "/" in client:
            parsed = ipaddress.ip_network(client, strict=False)
        else:
            parsed = ipaddress.ip_address(client)
    except ValueError as exc:
        raise ValueError("客户端 IP 或网段格式不正确") from exc
    if parsed.version != 4:
        raise ValueError("客户端白名单目前只支持 IPv4")
    normalized = str(parsed)
    if len(comment) > 120:
        raise ValueError("备注不能超过 120 个字符")
    return {"client": normalized, "comment": comment}


def restart_dnsmasq():
    subprocess.run(RESTART_CMD.split(), check=True)


def sync_firewall():
    subprocess.run(FIREWALL_SYNC_CMD.split(), check=True)


class Handler(BaseHTTPRequestHandler):
    server_version = "DnsAdmin/1.0"

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            self.send_text(INDEX_HTML, "text/html; charset=utf-8")
            return
        if path == "/api/records":
            if not self.authorized():
                self.send_json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
                return
            with LOCK:
                records = parse_hosts()
            self.send_json({"records": records, "count": len(records)})
            return
        if path == "/api/clients":
            if not self.authorized():
                self.send_json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
                return
            with LOCK:
                clients = parse_clients()
            self.send_json({"clients": clients, "count": len(clients)})
            return
        self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/clients":
            if not self.authorized():
                self.send_json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
                return
            try:
                client = validate_client(self.read_json())
                with LOCK:
                    clients = parse_clients()
                    if any(item["client"] == client["client"] for item in clients):
                        raise ValueError("客户端 IP 已存在")
                    clients.append(client)
                    write_clients(clients)
                    sync_firewall()
                self.send_json({"ok": True})
            except (ValueError, subprocess.CalledProcessError) as exc:
                self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
            return

        if path != "/api/records":
            self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
            return
        if not self.authorized():
            self.send_json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
            return
        try:
            record = validate_record(self.read_json())
            with LOCK:
                records = parse_hosts()
                if any(item["host"] == record["host"] for item in records):
                    raise ValueError("域名已存在")
                records.append(record)
                write_hosts(records)
                restart_dnsmasq()
            self.send_json({"ok": True})
        except (ValueError, subprocess.CalledProcessError) as exc:
            self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)

    def do_PUT(self):
        client = self.client_from_path()
        if client:
            if not self.authorized():
                self.send_json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
                return
            try:
                next_client = validate_client(self.read_json())
                with LOCK:
                    clients = [item for item in parse_clients() if item["client"] != client]
                    if next_client["client"] != client and any(item["client"] == next_client["client"] for item in clients):
                        raise ValueError("客户端 IP 已存在")
                    clients.append(next_client)
                    write_clients(clients)
                    sync_firewall()
                self.send_json({"ok": True})
            except (ValueError, subprocess.CalledProcessError) as exc:
                self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
            return

        host = self.record_host_from_path()
        if not host:
            self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
            return
        if not self.authorized():
            self.send_json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
            return
        try:
            record = validate_record(self.read_json())
            with LOCK:
                records = [item for item in parse_hosts() if item["host"] != host]
                if record["host"] != host and any(item["host"] == record["host"] for item in records):
                    raise ValueError("域名已存在")
                records.append(record)
                write_hosts(records)
                restart_dnsmasq()
            self.send_json({"ok": True})
        except (ValueError, subprocess.CalledProcessError) as exc:
            self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)

    def do_DELETE(self):
        client = self.client_from_path()
        if client:
            if not self.authorized():
                self.send_json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
                return
            try:
                with LOCK:
                    clients = [item for item in parse_clients() if item["client"] != client]
                    write_clients(clients)
                    sync_firewall()
                self.send_json({"ok": True})
            except subprocess.CalledProcessError as exc:
                self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
            return

        host = self.record_host_from_path()
        if not host:
            self.send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
            return
        if not self.authorized():
            self.send_json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
            return
        try:
            with LOCK:
                records = [item for item in parse_hosts() if item["host"] != host]
                write_hosts(records)
                restart_dnsmasq()
            self.send_json({"ok": True})
        except subprocess.CalledProcessError as exc:
            self.send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)

    def record_host_from_path(self):
        path = urlparse(self.path).path
        prefix = "/api/records/"
        if not path.startswith(prefix):
            return None
        from urllib.parse import unquote
        return unquote(path[len(prefix):]).strip().lower()

    def client_from_path(self):
        path = urlparse(self.path).path
        prefix = "/api/clients/"
        if not path.startswith(prefix):
            return None
        from urllib.parse import unquote
        return unquote(path[len(prefix):]).strip()

    def authorized(self):
        auth = self.headers.get("Authorization", "")
        return auth == f"Bearer {self.server.admin_token}"

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length).decode("utf-8") or "{}")

    def send_text(self, body, content_type):
        data = body.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, body, status=HTTPStatus.OK):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        return


def main():
    token = ensure_token()
    try:
        sync_firewall()
    except subprocess.CalledProcessError as exc:
        print(f"Firewall sync failed: {exc}")
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    server.admin_token = token
    print(f"DNS admin listening on http://{BIND}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
