#!/usr/bin/env python3
import asyncio
import os
import struct
from pathlib import Path


DOMAINS_FILE = Path(os.environ.get("DNS_UNLOCK_DOMAINS_FILE", "/opt/dns-service-onekey/config/unlock-domains.txt"))
LISTEN_HOST = os.environ.get("DNS_UNLOCK_PROXY_BIND", "0.0.0.0")
HTTP_PORT = int(os.environ.get("DNS_UNLOCK_HTTP_PORT", "80"))
HTTPS_PORT = int(os.environ.get("DNS_UNLOCK_HTTPS_PORT", "443"))


def load_domains():
    domains = []
    if DOMAINS_FILE.exists():
        for line in DOMAINS_FILE.read_text(encoding="utf-8").splitlines():
            domain = line.split("#", 1)[0].strip().lower()
            if domain:
                domains.append(domain)
    return tuple(sorted(set(domains)))


def allowed(host, domains):
    host = host.rstrip(".").lower()
    return any(host == domain or host.endswith("." + domain) for domain in domains)


def parse_http_host(data):
    try:
        header = data.split(b"\r\n\r\n", 1)[0].decode("latin1", "ignore")
    except UnicodeDecodeError:
        return None
    for line in header.split("\r\n")[1:]:
        if line.lower().startswith("host:"):
            host = line.split(":", 1)[1].strip()
            return host.rsplit(":", 1)[0] if host.count(":") <= 1 else host.strip("[]")
    return None


def parse_tls_sni(data):
    try:
        if len(data) < 5 or data[0] != 22:
            return None
        record_len = struct.unpack("!H", data[3:5])[0]
        body = data[5:5 + record_len]
        if len(body) < 42 or body[0] != 1:
            return None
        pos = 4 + 2 + 32
        session_len = body[pos]
        pos += 1 + session_len
        cipher_len = struct.unpack("!H", body[pos:pos + 2])[0]
        pos += 2 + cipher_len
        comp_len = body[pos]
        pos += 1 + comp_len
        ext_total = struct.unpack("!H", body[pos:pos + 2])[0]
        pos += 2
        end = pos + ext_total
        while pos + 4 <= end:
            ext_type = struct.unpack("!H", body[pos:pos + 2])[0]
            ext_len = struct.unpack("!H", body[pos + 2:pos + 4])[0]
            pos += 4
            ext = body[pos:pos + ext_len]
            pos += ext_len
            if ext_type != 0 or len(ext) < 5:
                continue
            list_len = struct.unpack("!H", ext[0:2])[0]
            item_pos = 2
            list_end = 2 + list_len
            while item_pos + 3 <= list_end:
                name_type = ext[item_pos]
                name_len = struct.unpack("!H", ext[item_pos + 1:item_pos + 3])[0]
                item_pos += 3
                name = ext[item_pos:item_pos + name_len]
                item_pos += name_len
                if name_type == 0:
                    return name.decode("idna").lower()
    except Exception:
        return None
    return None


async def relay(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def handle_client(reader, writer, mode, domains):
    peer = writer.get_extra_info("peername")
    try:
        first = await asyncio.wait_for(reader.read(4096), timeout=8)
        if not first:
            return
        host = parse_tls_sni(first) if mode == "tls" else parse_http_host(first)
        if not host or not allowed(host, domains):
            print(f"reject {mode} {peer} host={host}")
            return
        port = 443 if mode == "tls" else 80
        remote_reader, remote_writer = await asyncio.open_connection(host, port)
        remote_writer.write(first)
        await remote_writer.drain()
        await asyncio.gather(
            relay(reader, remote_writer),
            relay(remote_reader, writer),
        )
    except Exception as exc:
        print(f"proxy error {mode} {peer}: {exc}")
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def main():
    domains = load_domains()
    if not domains:
        raise SystemExit(f"no unlock domains loaded from {DOMAINS_FILE}")
    http_server = await asyncio.start_server(lambda r, w: handle_client(r, w, "http", domains), LISTEN_HOST, HTTP_PORT)
    tls_server = await asyncio.start_server(lambda r, w: handle_client(r, w, "tls", domains), LISTEN_HOST, HTTPS_PORT)
    print(f"DNS unlock proxy listening on {LISTEN_HOST}:{HTTP_PORT},{HTTPS_PORT}; domains={len(domains)}")
    async with http_server, tls_server:
        await asyncio.gather(http_server.serve_forever(), tls_server.serve_forever())


if __name__ == "__main__":
    asyncio.run(main())
