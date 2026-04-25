# DNS Service Onekey

一个可以放到 GitHub 上，让 Linux 服务器直接拉取安装的轻量 DNS 服务脚本。它基于 `dnsmasq`，适合做本机 DNS 缓存、局域网 DNS、简单自定义域名解析和 DNS 转发。

## 支持系统

- Debian / Ubuntu
- CentOS / Rocky Linux / AlmaLinux / Fedora
- 需要 `systemd`

## 服务器拉取安装

推荐用这个方式。服务器会自动从 GitHub 拉取完整仓库到 `/opt/dns-service-onekey-src`，然后安装 DNS 服务和 Web 管理面板。

把仓库推到 GitHub 后，将下面的地址替换成你的 GitHub 用户名和仓库名：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=你的用户名/dns-service-onekey bash
```

如果你想指定完整仓库地址：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main/bootstrap.sh | sudo env REPO_URL=https://github.com/你的用户名/dns-service-onekey.git bash
```

默认只监听本机：

```text
127.0.0.1:53
```

如果要让局域网或公网访问，请明确指定监听地址：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=你的用户名/dns-service-onekey LISTEN_ADDR=0.0.0.0 bash
```

如果这台服务器要作为 DNS 给其他服务器使用，推荐同时设置客户端白名单。把 `1.2.3.4,5.6.7.8` 换成允许使用 DNS 的服务器公网 IP：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=你的用户名/dns-service-onekey LISTEN_ADDR=0.0.0.0 CLIENT_ALLOWLIST=1.2.3.4,5.6.7.8 bash
```

安装后也可以直接在 Web 面板里的“允许 IP”页面增删这些服务器 IP，不需要重新安装。

如果想像常见 DNS 解锁项目一样，服务端预置域名规则，日常只管理允许使用的服务器 IP，可以安装时指定 `UNLOCK_TARGET_IP`。把 `154.64.225.137` 换成你的解锁/中转 IP：

```bash
curl -fsSL https://raw.githubusercontent.com/1660667086/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=1660667086/dns-service-onekey LISTEN_ADDR=0.0.0.0 ADMIN_BIND=0.0.0.0 UNLOCK_TARGET_IP=154.64.225.137 bash
```

这样会自动把 `config/unlock-domains.txt` 里的域名写成 `address=/域名/154.64.225.137`。之后你只需要在面板的 `允许 IP` 里加客户端服务器公网 IP。

安装完成后会同时启动 Web 管理面板，默认只监听本机：

```text
http://127.0.0.1:8080
```

登录 Token 在服务器上查看：

```bash
sudo cat /etc/dns-service/admin.token
```

如果要让局域网访问 Web 面板：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=你的用户名/dns-service-onekey ADMIN_BIND=0.0.0.0 ADMIN_PORT=8080 bash
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
| `ADMIN_BIND` | `127.0.0.1` | Web 管理面板监听地址 |
| `ADMIN_PORT` | `8080` | Web 管理面板端口 |
| `CLIENT_ALLOWLIST` | 空 | 允许访问 DNS 的客户端 IP，多个用英文逗号分隔 |
| `UNLOCK_TARGET_IP` | 空 | 预置解锁域名要解析到的目标 IP |
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

如果默认安装，面板只监听 `127.0.0.1`。可以通过 SSH 隧道访问：

```bash
ssh -L 8080:127.0.0.1:8080 root@服务器IP
```

然后在本地浏览器打开：

```text
http://127.0.0.1:8080
```

登录后有两个页面：

- `解析记录`：添加、编辑、删除域名解析
- `允许 IP`：添加、编辑、删除允许使用这个 DNS 的服务器 IP

解析记录示例：

```text
nas.lan -> 10.0.0.10
router.lan -> 192.168.1.1
```

每次保存后，面板会自动重写 `/etc/dns-service/conf.d/records.conf` 并重启 `dnsmasq`。记录会使用 `address=/域名/IP` 格式，效果接近你那台可用服务器的 `custom_netflix.conf`。

允许 IP 示例：

```text
1.2.3.4
5.6.7.8
10.0.0.0/24
```

每次保存后，面板会自动重写 `/etc/dns-service/clients.allow` 并同步防火墙规则。白名单为空时，外部服务器不能使用这个 DNS。

## 给其他服务器当 DNS

在 DNS 服务器上安装，假设 DNS 服务器公网 IP 是 `8.8.8.8`，允许使用它的客户端服务器公网 IP 是 `1.2.3.4` 和 `5.6.7.8`：

```bash
curl -fsSL https://raw.githubusercontent.com/1660667086/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=1660667086/dns-service-onekey LISTEN_ADDR=0.0.0.0 CLIENT_ALLOWLIST=1.2.3.4,5.6.7.8 bash
```

然后在客户端服务器上临时测试：

```bash
dig @8.8.8.8 example.com
```

如果要让客户端服务器长期使用这台 DNS，可以编辑客户端服务器的 DNS 配置。Ubuntu/Debian 常见方式：

```bash
sudo resolvectl dns eth0 8.8.8.8
sudo resolvectl domain eth0 '~.'
resolvectl status
```

如果系统直接使用 `/etc/resolv.conf`：

```bash
printf 'nameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf
```

云服务器还需要在云厂商安全组里放行 DNS 服务器的 `53/udp` 和 `53/tcp`，来源只填你的客户端服务器 IP，不要开放给全网。

客户端服务器也可以用一条命令自动设置 DNS。把 `8.8.8.8` 换成你的 DNS 解锁服务器 IP：

```bash
curl -fsSL https://raw.githubusercontent.com/1660667086/dns-service-onekey/main/client-set-dns.sh | sudo env DNS_SERVER=8.8.8.8 bash
```

所以最简流程是：

```text
1. DNS 解锁服务器安装时设置 UNLOCK_TARGET_IP
2. Web 面板只添加允许使用的客户端服务器 IP
3. 客户端服务器运行 client-set-dns.sh 一次
```

## 更新已安装服务

服务器已经安装过时，重新运行 bootstrap 会自动拉取 GitHub 最新代码并覆盖服务文件：

```bash
curl -fsSL https://raw.githubusercontent.com/1660667086/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=1660667086/dns-service-onekey LISTEN_ADDR=0.0.0.0 bash
```

如果你想保留并继续使用已有白名单，直接重新运行即可；已有 `/etc/dns-service/clients.allow` 会保留。

## 添加自定义解析

安装后编辑：

```bash
sudo nano /etc/dns-service/conf.d/records.conf
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
journalctl -u dnsmasq -f
journalctl -u dns-service-admin -f
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
