# DNS Service Onekey

一键安装“原版 Dnsmasq + SNI Proxy 解锁项目”，并额外加一个 Web 页面管理允许使用的客户端 IP。

核心安装使用公开原版脚本：

```text
https://github.com/myxuchangbin/dnsmasq_sniproxy_install
```

本项目只追加：

- Web 管理页面
- `/etc/dns-service/clients.allow` 允许 IP 文件
- iptables 白名单同步，限制 `53/80/443`

不会读取、复制或修改 `154.64.225.137` 那台服务器的任何文件。

## 一键安装

在新服务器执行：

```bash
curl -fsSL https://raw.githubusercontent.com/1660667086/dns-service-onekey/main/bootstrap.sh | sudo env GITHUB_REPO=1660667086/dns-service-onekey bash
```

安装完成后会有：

```text
/etc/dnsmasq.d/custom_netflix.conf
/etc/sniproxy.conf
/etc/dns-service/clients.allow
```

服务：

```bash
systemctl status dnsmasq
systemctl status sniproxy
systemctl status dns-service-admin
```

## Web 管理

打开：

```text
http://服务器IP:8080
```

查看登录 Token：

```bash
sudo cat /etc/dns-service/admin.token
```

Web 面板只管理 `允许 IP`。把要使用这个 DNS 解锁服务的客户端服务器公网 IP 加进去即可。

保存后会自动同步 iptables，限制只有允许 IP 可以访问：

```text
53/tcp
53/udp
80/tcp
443/tcp
```

## 云防火墙

云厂商安全组也要放行：

```text
53/udp
53/tcp
80/tcp
443/tcp
8080/tcp
```

建议 `53/80/443` 来源只填你的客户端服务器 IP。`8080` 是 Web 面板端口，也建议限制来源。

## 测试

在允许 IP 的客户端服务器上测试：

```bash
dig @你的DNS服务器IP netflix.com
dig @你的DNS服务器IP openai.com
```

返回新 DNS 服务器 IP，说明 dnsmasq 规则生效。

## 更新

重新执行一键安装命令即可。已有 `/etc/dns-service/clients.allow` 会保留，原版脚本会重新安装/刷新 `dnsmasq + sniproxy`。

## 卸载

```bash
cd /opt/dns-service-onekey-src
sudo bash uninstall.sh
```

删除 Web 管理数据：

```bash
sudo REMOVE_DATA=1 bash uninstall.sh
```
