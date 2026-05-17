# Cloudflare DDNS 一键脚本

支持 Debian / Ubuntu / Alpine 系统的动态 DNS 解析工具，配合 Cloudflare API Token 自动更新域名解析记录。

## 功能特点

- 支持 IPv4 和 IPv6 双栈解析
- 使用 Cloudflare API Token 认证（无需 Global Key）
- **任意域名自动匹配 Zone** — 无需手动指定根域名
- 支持多域名同时解析
- 支持 Telegram 和飞书双通道通知推送
- 可自定义更新间隔时间
- 支持 systemd（Debian/Ubuntu）和 cron（Alpine）两种定时方案

## 系统要求

- 操作系统：Debian / Ubuntu / Alpine
- 需以 root 身份运行
- 需拥有 Cloudflare API Token（DNS 编辑权限）

## 安装

bash
# 下载脚本
```
sudo curl -o /usr/bin/ddns https://raw.githubusercontent.com/semgooder/sem-ddns/main/ddns.sh && sudo chmod +x /usr/bin/ddns && ddns
```

# 运行
```
ddns
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

```
请输入您的Cloudflare API令牌（API Token）
请在 Cloudflare 控制面板 -> 我的资料 -> API 令牌 中创建或获取
API Token:
```

**Token 权限要求：**
- `Zone / DNS / Edit`（编辑 DNS 记录）
- `Zone / Zone / Read`（读取域名区域）

### 配置域名

选择选项 `4`，输入要解析的域名（多个域名用逗号分隔）：

```
请输入您要解析的IPv4域名（可解析多个域名，使用逗号分隔）
IPv4域名: example.com, blog.example.com
```

支持任意级别的域名，脚本会自动匹配对应的 Zone。例如输入 `sub.domain.example.com` 会自动找到 `example.com` 对应的区域。

### Telegram 通知（可选）

选择选项 `6`，依次输入 Bot Token 和 Chat ID：

- Bot Token：在 [@BotFather](https://t.me/BotFather) 创建机器人获取
- Chat ID：向机器人发送任意消息后，访问 `https://api.telegram.org/bot<你的Token>/getUpdates` 获取

### 飞书通知（可选）

选择选项 `8`，输入飞书机器人 Webhook 地址：

```
请输入您的飞书机器人 Webhook 地址
在飞书群组 -> 设置 -> 群机器人 -> 添加机器人 -> 自定义机器人 中获取 Webhook 地址
Webhook:
```

如果开启了签名校验，还会提示输入 Secret：

```
请输入您的飞书机器人签名密钥（Secret）
在飞书机器人设置 -> 安全设置 -> 签名校验 中获取
Secret:
```

**获取方式：**
1. 飞书群组 → 设置 → 群机器人 → 添加机器人 → 自定义机器人 → 复制 Webhook 地址
2. 在机器人安全设置中开启**签名校验**，复制 Secret
3. 配置时输入 Webhook 地址，Secret 可选（不填则不签名）

### 自定义更新间隔

选择选项 `7`，输入分钟数：

```
请输入新的 DDNS 运行间隔（分钟）：5
```

## 配置文件

配置文件路径：`/etc/DDNS/.config`

```bash
Domains=("example.com" "blog.example.com")    # IPv4 域名
ipv6_set="true"                                # IPv6 开关
Domainsv6=("ipv6.example.com")                 # IPv6 域名
API_Token="your_api_token"                     # Cloudflare API 令牌
Telegram_Bot_Token=""                          # Telegram Bot Token
Telegram_Chat_ID=""                            # Telegram Chat ID
Feishu_Webhook=""                              # 飞书 Webhook 地址
Feishu_Secret=""                              # 飞书签名密钥（可选）
```

## 工作原理

1. 脚本通过 `ip.sb` 或 `api.ipify.org` 获取当前公网 IP
2. 调用 Cloudflare API 拉取所有域名区域，自动匹配域名对应的 Zone
3. 查询现有 DNS 记录 ID
4. 更新 DNS 记录为当前公网 IP
5. IP 变化时通过 Telegram 和/或飞书发送通知（如果已配置）

## 常见问题

**Q：如何获取 Cloudflare API Token？**

A：登录 Cloudflare 控制面板 → 右上角"我的资料" → "API 令牌" → "创建令牌"，选择"编辑 DNS 记录"模板，权限选择对应的域名区域，创建后保存生成的 Token。

**Q：支持泛域名解析吗？**

A：不支持。需要分别输入每个具体的子域名。

**Q：如何查看运行日志？**

A：在 Debian/Ubuntu 上使用 `journalctl -u ddns.service` 查看。

## 卸载

在菜单中选 `3` 即可完全卸载，或手动执行：

```bash
# Debian/Ubuntu
systemctl stop ddns.service ddns.timer
rm -rf /etc/systemd/system/ddns.service /etc/systemd/system/ddns.timer /etc/DDNS /usr/bin/ddns

# Alpine
crontab -l | grep -v "/bin/bash /etc/DDNS/DDNS" | crontab -
rm -rf /etc/DDNS /usr/bin/ddns
```

## License

MIT
