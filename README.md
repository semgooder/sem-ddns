# Cloudflare DDNS

支持 **Linux**（bash）和 **Windows / Linux / macOS**（Go 编译版）的动态 DNS 解析工具。

## 功能特点

- 支持 IPv4 和 IPv6 双栈解析
- 支持三大 DNS 服务商：
  - **Cloudflare**（API Token）
  - **DNSPod 独立版**（ID + Token）
  - **腾讯云 DNSPod**（SecretId + SecretKey，API 3.0）
- **任意域名自动匹配 Zone** — 无需手动指定根域名
- 支持多域名同时解析
- 支持 Telegram 和飞书双通道通知推送（飞书支持 HMAC-SHA256 签名校验）
- **Go 版**内置 Windows 服务，无需 NSSM，开机自启
- **Go 版**跨平台编译，一个二进制到处运行

## 系统要求

- **Linux 脚本版**: Debian / Ubuntu / Alpine，需 root 权限
- **Go 版**: Windows 7+ / Linux / macOS，无需任何依赖

---

# Linux 版 (bash)

## 安装

```bash
sudo curl -o /usr/bin/ddns https://raw.githubusercontent.com/semgooder/sem-ddns/main/ddns.sh
sudo chmod +x /usr/bin/ddns
sudo ddns
```

首次运行自动创建运行脚本，直接进入菜单。之后通过菜单选项自行配置。

> 注意：bash 版仅支持 **Cloudflare**。如需使用 **DNSPod** 或 **腾讯云 DNSPod**，请使用下方的 Go 版。

### 主菜单

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

### 配置文件

路径：`/etc/DDNS/.config`，安装后自动生成，需手动配置凭证与域名。

### 卸载

菜单选 `3` 或手动 `systemctl stop ddns.service ddns.timer` 后删除相关文件。

---

# Go 版 (跨平台)

## 安装

### 预编译（Windows 推荐）

```powershell
curl -o ddns.exe https://github.com/semgooder/sem-ddns/releases/latest/download/ddns-windows-amd64.exe
.\ddns.exe
```

### 自行编译

需要 Go 1.21+ 环境：

```bash
git clone https://github.com/semgooder/sem-ddns.git
cd sem-ddns/ddns

# 编译当前平台
go build -o ddns .

# 交叉编译 Windows
GOOS=windows GOARCH=amd64 go build -o ddns-windows-amd64.exe .

# 交叉编译 Linux
GOOS=linux GOARCH=amd64 go build -o ddns-linux-amd64 .

# 交叉编译 macOS
GOOS=darwin GOARCH=amd64 go build -o ddns-macos-amd64 .
```

### 首次运行

直接执行即可进入菜单，无需强制配置：

```bash
# Windows
ddns.exe

# Linux / macOS
./ddns
```

首次运行会自动创建空配置文件，之后在菜单中按需配置即可。

## 使用指南

### 交互菜单

```
 0：退出
 1：立即执行 DDNS 更新
 2：切换 DNS 服务商
 3：配置 DNS 凭证
 4：配置要解析的域名
 5：配置 Telegram 通知
 6：配置飞书通知
 7：安装 Windows 服务（开机自启）
 8：卸载 Windows 服务
```

典型配置流程：
1. 选 **`2`** 切换 DNS 服务商（Cloudflare / DNSPod / 腾讯云）
2. 选 **`3`** 输入对应凭证
3. 选 **`4`** 添加要解析的域名
4. 可选配置通知（`5` Telegram / `6` 飞书）
5. 选 **`1`** 立即执行更新测试

### 命令行模式（无界面，适合自动化）

```bash
# 执行一次 DDNS 更新
ddns run

# 安装 Windows 服务（原生，无需 NSSM）
ddns install

# 卸载 Windows 服务
ddns uninstall

# 重新运行配置向导
ddns config
```

### Windows 原生服务

运行 `ddns install` 即可注册为 Windows 系统服务，无需 NSSM 或任何第三方工具：
- 服务名称：`CloudflareDDNS`
- 启动类型：**自动**（开机自启）
- 运行身份：**LocalSystem**
- 每 **5 分钟**执行一次 DDNS 更新
- 在 `services.msc` 中可启停管理

## 配置文件

路径：`%USERPROFILE%\.ddns\config.json`（Windows）或 `~/.ddns/config.json`（Linux/macOS）

```json
{
  "Provider": "cloudflare",
  "API_Token": "your_api_token",
  "DNSPod_ID": "",
  "DNSPod_Token": "",
  "SecretId": "",
  "SecretKey": "",
  "Domains": ["example.com", "blog.example.com"],
  "ipv6_set": "true",
  "Domainsv6": ["ipv6.example.com"],
  "Telegram_Bot_Token": "",
  "Telegram_Chat_ID": "",
  "Feishu_Webhook": "",
  "Feishu_Secret": ""
}
```

> `Provider` 可选值：`cloudflare`（默认）、`dnspod`、`tencentcloud`

## 日志

日志路径：`%USERPROFILE%\.ddns\ddns.log`（Windows）或 `~/.ddns/ddns.log`（Linux/macOS）

## 卸载

```bash
# 卸载服务（Windows）
ddns uninstall

# 删除配置和日志
rm -rf ~/.ddns

# 删除程序
rm ddns
```

---

# 项目结构

| 文件 | 说明 |
|------|------|
| `ddns.sh` | Linux bash 版主脚本 |
| `ddns/` | Go 版源码 |
| `ddns/main.go` | CLI 入口 + 交互菜单 |
| `ddns/config.go` | JSON 配置读写 |
| `ddns/ip.go` | 公网 IPv4/IPv6 检测 |
| `ddns/provider.go` | DNS 服务商接口定义 |
| `ddns/cloudflare.go` | Cloudflare 实现 |
| `ddns/dnspod.go` | DNSPod 独立版实现 |
| `ddns/tencentcloud.go` | 腾讯云 DNSPod (API 3.0) 实现 |
| `ddns/notify.go` | Telegram + 飞书通知 |
| `ddns/updater.go` | DDNS 核心更新逻辑 |
| `ddns/service_windows.go` | 原生 Windows 服务注册 |
| `ddns/service_stub.go` | 非 Windows 平台服务占位 |

# 工作原理

1. 获取当前公网 IP（IPv4 / IPv6）
2. 调用对应 DNS 服务商 API 获取域名列表，自动匹配域名所属区域
3. 查询现有 DNS 记录 ID
4. 更新 DNS 记录为当前公网 IP
5. IP 变化时通过 Telegram 和/或飞书发送通知

# 常见问题

**Q：如何获取 Cloudflare API Token？**

A：Cloudflare 控制面板 -> 我的资料 -> API 令牌 -> 创建令牌，选择"编辑 DNS 记录"模板，权限选 `Zone:DNS:Edit` + `Zone:Zone:Read`。

**Q：如何获取 DNSPod 凭证？**

A：DNSPod 控制台 -> 安全设置 -> API 密钥 -> 创建密钥，获取 ID 和 Token（独立版 API 用）。

**Q：如何获取腾讯云 DNSPod 凭证？**

A：腾讯云控制台 -> 访问管理 -> 访问密钥 -> API 密钥管理，创建 SecretId 和 SecretKey。

**Q：支持泛域名解析吗？**

A：不支持，需要输入具体的子域名。

**Q：如何查看运行日志？**

A：Linux 脚本版用 `journalctl -u ddns.service`；Go 版日志在 `~/.ddns/ddns.log`。

**Q：Go 版需要安装 Go 环境才能用吗？**

A：不需要。下载编译好的 exe 即可直接运行。只有自行编译才需要 Go 环境。

# License

MIT
