# Cloudflare DDNS

支持 **Linux**（bash）和 **Windows**（PowerShell）的动态 DNS 解析工具，配合 Cloudflare API Token 自动更新域名解析记录。

## 功能特点

- 支持 IPv4 和 IPv6 双栈解析
- 使用 Cloudflare API Token 认证（无需 Global Key）
- **任意域名自动匹配 Zone** — 无需手动指定根域名
- 支持多域名同时解析
- 支持 Telegram 和飞书双通道通知推送（飞书支持 HMAC-SHA256 签名校验）
- Linux 版支持 systemd / cron 定时方案
- Windows 版支持 Task Scheduler 计划任务（每5分钟 + 开机自启）

## 系统要求

- **Linux**: Debian / Ubuntu / Alpine，需 root 权限
- **Windows**: Windows 7+ / Windows Server 2012+（PowerShell 5.1+）
- 需拥有 Cloudflare API Token（DNS 编辑权限）

---

# Linux 版 (bash)

## 安装

```bash
sudo curl -o /usr/bin/ddns https://raw.githubusercontent.com/semgooder/sem-ddns/main/ddns.sh
sudo chmod +x /usr/bin/ddns
sudo ddns
```

首次运行会自动创建配置文件并根据引导完成配置。

## 使用指南

### 主菜单

运行 `ddns` 进入交互菜单：

```
0：退出
1：重启 DDNS
2：停止 DDNS
3：卸载 DDNS
4：修改要解析的域名
5：配置 Cloudflare API Token
6：配置 Telegram 通知
7：更改 DDNS 运行时间
8：配置飞书通知
```

### 配置 Cloudflare API Token

选择选项 `5`，输入你的 API Token：

**Token 权限要求：**
- `Zone / DNS / Edit`
- `Zone / Zone / Read`

### 配置域名

选择选项 `4`，输入要解析的域名（多个用逗号分隔）。支持任意级别的域名，脚本会自动匹配对应的 Zone。

### Telegram / 飞书通知

分别对应选项 `6` 和 `8`，按提示输入 Bot Token / Chat ID 或 Webhook 地址即可。

### 自定义更新间隔

选择选项 `7`，输入分钟数。

## 配置文件

路径：`/etc/DDNS/.config`

```bash
Domains=("example.com" "blog.example.com")
ipv6_set="true"
Domainsv6=("ipv6.example.com")
API_Token="your_api_token"
Telegram_Bot_Token=""
Telegram_Chat_ID=""
Feishu_Webhook=""
Feishu_Secret=""
```

## 卸载

菜单选 `3` 或手动：

```bash
# Debian/Ubuntu
systemctl stop ddns.service ddns.timer
rm -rf /etc/systemd/system/ddns.service /etc/systemd/system/ddns.timer /etc/DDNS /usr/bin/ddns

# Alpine
crontab -l | grep -v "/bin/bash /etc/DDNS/DDNS" | crontab -
rm -rf /etc/DDNS /usr/bin/ddns
```

---

# Windows 版 (PowerShell)

## 安装

```powershell
# 下载脚本到用户目录
curl -o "$env:USERPROFILE\ddns.ps1" https://raw.githubusercontent.com/semgooder/sem-ddns/main/ddns.ps1

# 首次运行（自动进入配置向导）
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ddns.ps1"
```

> 如果遇到执行策略限制，先运行：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

## 使用指南

### 交互菜单

运行后显示菜单：

```
0：退出
1：立即执行 DDNS 更新
2：配置 Cloudflare API Token
3：配置要解析的域名
4：配置 Telegram 通知
5：配置飞书通知
6：安装计划任务（每5分钟运行 + 开机自启）
7：卸载计划任务
```

### 命令行参数

```powershell
# 直接执行 DDNS 更新（适合计划任务调用）
.\ddns.ps1 -Run

# 安装计划任务
.\ddns.ps1 -Install

# 卸载计划任务
.\ddns.ps1 -Uninstall
```

### 计划任务

安装后会自动创建名为 `CloudflareDDNS` 的计划任务：
- **每 5 分钟**执行一次 DDNS 更新
- **开机时**自动运行
- 可在 `taskschd.msc` 中查看和管理

## 配置文件

路径：`%USERPROFILE%\.ddns\config.json`

```json
{
  "API_Token": "your_api_token",
  "Domains": ["example.com", "blog.example.com"],
  "ipv6_set": "true",
  "Domainsv6": ["ipv6.example.com"],
  "Telegram_Bot_Token": "",
  "Telegram_Chat_ID": "",
  "Feishu_Webhook": "",
  "Feishu_Secret": "",
  "Public_IPv4": "",
  "Public_IPv6": ""
}
```

## 卸载

```powershell
# 删除计划任务
.\ddns.ps1 -Uninstall

# 删除配置文件
Remove-Item "$env:USERPROFILE\.ddns" -Recurse -Force

# 删除脚本
Remove-Item "$env:USERPROFILE\ddns.ps1" -Force
```

---

# 工作原理

1. 获取当前公网 IP（IPv4 / IPv6）
2. 调用 Cloudflare API 拉取所有域名区域，自动匹配域名对应的 Zone
3. 查询现有 DNS 记录 ID
4. 更新 DNS 记录为当前公网 IP
5. IP 变化时通过 Telegram 和/或飞书发送通知

# 常见问题

**Q：如何获取 Cloudflare API Token？**

A：Cloudflare 控制面板 → 我的资料 → API 令牌 → 创建令牌，选择"编辑 DNS 记录"模板。

**Q：Token 需要什么权限？**

A：`Zone / DNS / Edit` 和 `Zone / Zone / Read` 即可。

**Q：支持泛域名解析吗？**

A：不支持，需要分别输入每个具体的子域名。

**Q：如何查看运行日志？**

A：Linux: `journalctl -u ddns.service`；Windows: `%USERPROFILE%\.ddns\ddns.log`。

# License

MIT
