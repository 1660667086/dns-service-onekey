# DNS Service Onekey

一个可以放到 GitHub 上，让 Linux 服务器直接拉取安装的轻量 DNS 服务脚本。它基于 `dnsmasq`，适合做本机 DNS 缓存、局域网 DNS、简单自定义域名解析和 DNS 转发。

## 支持系统

- Debian / Ubuntu
- CentOS / Rocky Linux / AlmaLinux / Fedora
- 需要 `systemd`

## 一键安装

把仓库推到 GitHub 后，将下面的地址替换成你的 GitHub 用户名和仓库名：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main/install.sh | sudo bash
```

默认只监听本机：

```text
127.0.0.1:53
```

如果要让局域网或公网访问，请明确指定监听地址：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main/install.sh | sudo env LISTEN_ADDR=0.0.0.0 bash
```

## 自定义安装参数

```bash
sudo LISTEN_ADDR=0.0.0.0 \
  DNS_PORT=53 \
  UPSTREAM_DNS="1.1.1.1,8.8.8.8,223.5.5.5" \
  CACHE_SIZE=10000 \
  bash install.sh
```

参数说明：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `LISTEN_ADDR` | `127.0.0.1` | DNS 监听地址，公网服务可设为 `0.0.0.0` |
| `DNS_PORT` | `53` | DNS 监听端口 |
| `UPSTREAM_DNS` | `1.1.1.1,8.8.8.8` | 上游 DNS，多个用英文逗号分隔 |
| `CACHE_SIZE` | `10000` | DNS 缓存条数 |
| `LOG_QUERIES` | `0` | 设为 `1` 后记录查询日志 |

## Git clone 安装

```bash
git clone https://github.com/你的用户名/dns-service-onekey.git
cd dns-service-onekey
sudo bash install.sh
```

## 添加自定义解析

安装后编辑：

```bash
sudo nano /etc/dns-service/hosts
```

示例：

```text
1.2.3.4 example.test
10.0.0.10 nas.lan
```

重启服务：

```bash
sudo systemctl restart dnsmasq
```

## 测试

```bash
dig @127.0.0.1 example.com
```

如果监听的是公网或局域网地址：

```bash
dig @服务器IP example.com
```

## 查看状态

```bash
systemctl status dnsmasq
journalctl -u dnsmasq -f
```

## 卸载

```bash
sudo bash uninstall.sh
```

删除配置数据：

```bash
sudo REMOVE_DATA=1 bash uninstall.sh
```

## 安全提醒

不要随便把 DNS 服务开放到公网。公网开放 DNS 容易被滥用做放大攻击。更推荐：

- 只监听 `127.0.0.1` 给本机用
- 只监听内网 IP 给局域网用
- 如果必须公网开放，请在防火墙里限制允许访问的客户端 IP
