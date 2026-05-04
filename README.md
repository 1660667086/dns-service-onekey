# DNS Service Onekey

一个可以放到 GitHub 上，让 Linux 服务器直接拉取安装的 DNS 解锁服务。它按教程方式使用 `dnsmasq + sniproxy`：`dnsmasq` 做域名解析，`sniproxy` 接住 80/443 流量，并提供 Web 面板管理允许使用的客户端 IP。

## 支持系统

- Debian / Ubuntu
- CentOS / Rocky Linux / AlmaLinux / Fedora
- 需要 `systemd`

## 服务器拉取安装

推荐用这个方式。服务器会自动从 GitHub 拉取完整仓库到 `/opt/dns-service-onekey-src`，然后安装 DNS 解锁服务和 Web 管理面板。

直接在新服务器执行：

```bash
curl -fsSL https://raw.githubusercontent.com/1660667086/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=1660667086/dns-service-onekey bash
```

默认会自动完成：

- DNS 监听 `0.0.0.0:53`
- `sniproxy` 监听 `0.0.0.0:80` 和 `0.0.0.0:443`
- Web 面板监听 `0.0.0.0:8080`
- 自动检测本机公网 IP 作为 `UNLOCK_TARGET_IP`
- 自动生成 `address=/域名/本机公网IP` 解锁规则
- Web 面板只管理允许使用 DNS 的客户端 IP

安装完成后打开：

```text
http://服务器IP:8080
```

登录 Token 在服务器上查看：

```bash
sudo cat /etc/dns-service/admin.token
```

如果自动识别的公网 IP 不对，才需要手动指定：

```bash
curl -fsSL https://raw.githubusercontent.com/1660667086/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=1660667086/dns-service-onekey UNLOCK_TARGET_IP=你的服务器公网IP bash
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
| `LISTEN_ADDR` | `0.0.0.0` | DNS 监听地址 |
| `DNS_PORT` | `53` | DNS 监听端口 |
| `UPSTREAM_DNS` | `1.1.1.1,8.8.8.8` | 上游 DNS，多个用英文逗号分隔 |
| `CACHE_SIZE` | `10000` | DNS 缓存条数 |
| `LOG_QUERIES` | `0` | 设为 `1` 后记录查询日志 |
| `ADMIN_BIND` | `0.0.0.0` | Web 管理面板监听地址 |
| `ADMIN_PORT` | `8080` | Web 管理面板端口 |
| `CLIENT_ALLOWLIST` | 空 | 允许访问 DNS 的客户端 IP，多个用英文逗号分隔 |
| `UNLOCK_TARGET_IP` | 自动检测 | 预置解锁域名要解析到的目标 IP |
| `GITHUB_REPO` | 空 | GitHub 仓库，例如 `你的用户名/dns-service-onekey` |
| `REPO_URL` | 空 | 完整 Git 仓库地址 |
| `BRANCH` | `main` | 要安装的分支 |
| `INSTALL_DIR` | `/opt/dns-service-onekey-src` | 服务器上的源码拉取目录 |

## 直接运行 install.sh

如果你只想通过 raw 文件安装，也可以运行：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main/install.sh | sudo env RAW_BASE=https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main bash
```

不过更推荐使用 `bootstrap.sh`，因为它会把完整仓库拉到服务器上，后续更新也更方便。

## Git clone 安装

```bash
git clone https://github.com/你的用户名/dns-service-onekey.git
cd dns-service-onekey
sudo bash install.sh
```

Git clone 安装时不需要设置 `RAW_BASE`，脚本会直接复制仓库里的 Web 面板文件。

## Web 可视化管理

打开：

```text
http://服务器IP:8080
```

登录后只管理 `允许 IP`：添加、编辑、删除允许使用这个 DNS 的服务器 IP。

域名解锁规则不在面板里改。安装时会自动检测本机公网 IP，并把 `config/proxy-domains.txt` 里的域名写入 `/etc/dnsmasq.d/custom_netflix.conf`，格式是 `address=/域名/IP`，效果接近你那台可用服务器的 `custom_netflix.conf`。

这些域名会解析到新服务器自己，然后由 `sniproxy` 在 80/443 端口按 HTTP Host 或 TLS SNI 转发到真实目标站点。整个项目不读取、不复制、不修改 `154.64.225.137` 那台服务器的任何文件。

允许 IP 示例：

```text
1.2.3.4
5.6.7.8
10.0.0.0/24
```

每次保存后，面板会自动重写 `/etc/dns-service/clients.allow` 并同步防火墙规则。白名单为空时，外部服务器不能使用这个 DNS，也不能访问 80/443 解锁转发服务。

## 测试 DNS

```bash
dig @服务器IP openai.com
```

云服务器还需要在云厂商安全组里放行 `53/udp`、`53/tcp`、`80/tcp`、`443/tcp` 和面板端口 `8080/tcp`。`53/80/443` 的来源建议只填你的客户端服务器 IP，不要开放给全网。

## 更新已安装服务

服务器已经安装过时，重新运行 bootstrap 会自动拉取 GitHub 最新代码并覆盖服务文件：

```bash
curl -fsSL https://raw.githubusercontent.com/1660667086/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=1660667086/dns-service-onekey bash
```

如果你想保留并继续使用已有白名单，直接重新运行即可；已有 `/etc/dns-service/clients.allow` 会保留。

## 添加自定义解析

安装后编辑：

```bash
sudo nano /etc/dnsmasq.d/custom_netflix.conf
```

示例：

```text
address=/example.test/1.2.3.4
address=/nas.lan/10.0.0.10
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
systemctl status dns-service-admin
systemctl status sniproxy
journalctl -u dnsmasq -f
journalctl -u dns-service-admin -f
journalctl -u sniproxy -f
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
- 如果必须公网开放，请设置 `CLIENT_ALLOWLIST`，并在云防火墙里限制允许访问的客户端 IP
