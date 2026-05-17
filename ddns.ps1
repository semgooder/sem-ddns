param(
    [switch]$Run,
    [switch]$Install,
    [switch]$Uninstall
)

$ConfigPath = Join-Path $env:USERPROFILE ".ddns\config.json"
$LogPath = Join-Path $env:USERPROFILE ".ddns\ddns.log"
$RunScriptPath = Join-Path $env:USERPROFILE ".ddns\ddns-run.ps1"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$time][$Level] $Message"
    Write-Host $line
    if ($Level -eq "ERROR") {
        Add-Content -Path $LogPath -Value $line
    } else {
        Add-Content -Path $LogPath -Value $line
    }
}

function Write-Info { Write-Log @args -Level "INFO" }
function Write-Error { Write-Log @args -Level "ERROR" }
function Write-Warn { Write-Log @args -Level "WARN" }

function Read-Config {
    if (Test-Path $ConfigPath) {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        return $json
    }
    return $null
}

function Save-Config {
    param($Config)
    $dir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Config | ConvertTo-Json -Depth 3 | Set-Content $ConfigPath -Encoding UTF8
}

# ===================== 获取公网 IP =====================

function Get-PublicIPv4 {
    $urls = @("https://api.ipify.org", "https://ip.sb", "https://ipv4.icanhazip.com")
    foreach ($url in $urls) {
        try {
            $ip = (Invoke-RestMethod -Uri $url -TimeoutSec 5).Trim()
            if ($ip -match '^(\d{1,3}\.){3}\d{1,3}$') { return $ip }
        } catch {}
    }
    return $null
}

function Get-PublicIPv6 {
    $urls = @("https://api6.ipify.org", "https://ip.sb")
    foreach ($url in $urls) {
        try {
            $result = Invoke-RestMethod -Uri $url -TimeoutSec 5
            $ip = $result.Trim()
            if ($ip -match '^([0-9a-fA-F]{1,4}:){1,}[0-9a-fA-F]{0,4}') { return $ip }
        } catch {}
    }
    return $null
}

# ===================== Cloudflare API =====================

function Get-CfZoneId {
    param([string]$Domain, [string]$Token)
    try {
        $headers = @{ "Authorization" = "Bearer $Token"; "Content-Type" = "application/json" }
        $resp = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones" -Headers $headers -TimeoutSec 10
        if (-not $resp.success) { return $null }

        # 按域名后缀从长到短匹配，确保精确匹配
        $sorted = $resp.result | Sort-Object { $_.name.Length } -Descending
        foreach ($zone in $sorted) {
            if ($Domain -eq $zone.name -or $Domain.EndsWith(".$($zone.name)")) {
                return $zone.id
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Get-CfDnsRecordId {
    param([string]$ZoneId, [string]$Type, [string]$Name, [string]$Token)
    try {
        $headers = @{ "Authorization" = "Bearer $Token"; "Content-Type" = "application/json" }
        $uri = "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records?type=$Type&name=$Name"
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 10
        if ($resp.success -and $resp.result.Count -gt 0) {
            return $resp.result[0].id
        }
        return $null
    } catch {
        return $null
    }
}

function Update-CfDnsRecord {
    param([string]$ZoneId, [string]$RecordId, [string]$Type, [string]$Name, [string]$Content, [string]$Token)
    try {
        $headers = @{ "Authorization" = "Bearer $Token"; "Content-Type" = "application/json" }
        $body = @{ type = $Type; name = $Name; content = $Content } | ConvertTo-Json
        $uri = "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records/$RecordId"
        $resp = Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body $body -TimeoutSec 10
        return $resp.success
    } catch {
        return $false
    }
}

# ===================== 通知 =====================

function Send-Telegram {
    param([string]$BotToken, [string]$ChatId, [string]$Message)
    try {
        $uri = "https://api.telegram.org/bot$BotToken/sendMessage"
        $body = @{ chat_id = $ChatId; text = $Message } | ConvertTo-Json
        $headers = @{ "Content-Type" = "application/json" }
        Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -TimeoutSec 10 | Out-Null
    } catch {}
}

function Send-Feishu {
    param([string]$Webhook, [string]$Secret, [string]$Message)
    try {
        $body = @{ msg_type = "text"; content = @{ text = $Message } }

        if (-not [string]::IsNullOrEmpty($Secret)) {
            $timestamp = [Math]::Floor([DateTime]::UtcNow.Subtract([DateTime]"1970-01-01").TotalSeconds).ToString()
            $signString = "$timestamp`n$Secret"
            $hmac = New-Object System.Security.Cryptography.HMACSHA256
            $hmac.Key = [Text.Encoding]::UTF8.GetBytes($Secret)
            $hash = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($signString))
            $sign = [Convert]::ToBase64String($hash)
            $body.timestamp = $timestamp
            $body.sign = $sign
        }

        $headers = @{ "Content-Type" = "application/json" }
        Invoke-RestMethod -Uri $Webhook -Method POST -Headers $headers -Body ($body | ConvertTo-Json) -TimeoutSec 10 | Out-Null
    } catch {}
}

function Build-NotifyMessage {
    param($Config, $OldIPv4, $NewIPv4, $OldIPv6, $NewIPv6)
    $parts = @()
    if ($Config.Domains) { $parts += ($Config.Domains -join " ") }
    if ($NewIPv4 -and $NewIPv4 -ne $OldIPv4) { $parts += "IPv4更新 $OldIPv4 -> $NewIPv4" }
    if ($Config.ipv6_set -and $NewIPv6 -and $NewIPv6 -ne $OldIPv6) {
        if ($Config.Domainsv6 -and ($Config.Domains -join "") -ne ($Config.Domainsv6 -join "")) {
            $parts += ($Config.Domainsv6 -join " ")
        }
        $parts += "IPv6更新 $OldIPv6 -> $NewIPv6"
    }
    return ($parts -join " 。")
}

# ===================== DDNS 核心逻辑 =====================

function Invoke-DdnsUpdate {
    Write-Info "===== DDNS 更新开始 ====="
    $config = Read-Config
    if (-not $config -or [string]::IsNullOrEmpty($config.API_Token)) {
        Write-Error "配置文件不存在或未配置 API Token，请先运行 ddns.ps1 进行配置"
        return
    }

    $newIPv4 = Get-PublicIPv4
    $newIPv6 = $null
    if ($config.ipv6_set -eq "true") { $newIPv6 = Get-PublicIPv6 }

    Write-Info "当前公网 IPv4: $newIPv4"
    if ($newIPv6) { Write-Info "当前公网 IPv6: $newIPv6" }

    $oldIPv4 = $config.Public_IPv4
    $oldIPv6 = $config.Public_IPv6
    $changed = $false

    # 更新 IPv4
    if ($newIPv4 -and $config.Domains -and $config.Domains.Count -gt 0) {
        foreach ($domain in $config.Domains) {
            $zoneId = Get-CfZoneId -Domain $domain -Token $config.API_Token
            if (-not $zoneId) { Write-Error "未找到 $domain 对应的 Zone，请检查 API Token 权限"; continue }

            $recordId = Get-CfDnsRecordId -ZoneId $zoneId -Type "A" -Name $domain -Token $config.API_Token
            if (-not $recordId) { Write-Warn "未找到 $domain 的 A 记录，请先在 Cloudflare 控制面板添加"; continue }

            $ok = Update-CfDnsRecord -ZoneId $zoneId -RecordId $recordId -Type "A" -Name $domain -Content $newIPv4 -Token $config.API_Token
            if ($ok) { Write-Info "$domain -> $newIPv4 更新成功" } else { Write-Error "$domain -> $newIPv4 更新失败" }
        }
        if ($newIPv4 -ne $oldIPv4) { $changed = $true; $config.Public_IPv4 = $newIPv4 }
    }

    # 更新 IPv6
    if ($config.ipv6_set -eq "true" -and $newIPv6 -and $config.Domainsv6 -and $config.Domainsv6.Count -gt 0) {
        foreach ($domain in $config.Domainsv6) {
            $zoneId = Get-CfZoneId -Domain $domain -Token $config.API_Token
            if (-not $zoneId) { Write-Error "未找到 $domain 对应的 Zone，请检查 API Token 权限"; continue }

            $recordId = Get-CfDnsRecordId -ZoneId $zoneId -Type "AAAA" -Name $domain -Token $config.API_Token
            if (-not $recordId) { Write-Warn "未找到 $domain 的 AAAA 记录，请先在 Cloudflare 控制面板添加"; continue }

            $ok = Update-CfDnsRecord -ZoneId $zoneId -RecordId $recordId -Type "AAAA" -Name $domain -Content $newIPv6 -Token $config.API_Token
            if ($ok) { Write-Info "$domain -> $newIPv6 更新成功" } else { Write-Error "$domain -> $newIPv6 更新失败" }
        }
        if ($newIPv6 -ne $oldIPv6) { $changed = $true; $config.Public_IPv6 = $newIPv6 }
    }

    # 发送通知
    if ($changed) {
        $msg = Build-NotifyMessage -Config $config -OldIPv4 $oldIPv4 -NewIPv4 $newIPv4 -OldIPv6 $oldIPv6 -NewIPv6 $newIPv6

        if ($config.Telegram_Bot_Token -and $config.Telegram_Chat_ID) {
            Send-Telegram -BotToken $config.Telegram_Bot_Token -ChatId $config.Telegram_Chat_ID -Message $msg
            Write-Info "Telegram 通知已发送"
        }
        if ($config.Feishu_Webhook) {
            Send-Feishu -Webhook $config.Feishu_Webhook -Secret $config.Feishu_Secret -Message $msg
            Write-Info "飞书通知已发送"
        }
    }

    Save-Config $config
    Write-Info "===== DDNS 更新完成 ====="
}

# ===================== 交互配置 =====================

function Set-CloudflareApi {
    Write-Host "`n========== Cloudflare API 配置 ==========" -ForegroundColor Cyan
    $token = Read-Host "请输入您的 Cloudflare API Token（在 Cloudflare 控制面板 -> 我的资料 -> API 令牌 中获取）"
    if ([string]::IsNullOrEmpty($token)) { Write-Error "API Token 不能为空"; return }

    $config = Read-Config
    if (-not $config) { $config = New-Object PSObject }
    $config | Add-Member -MemberType NoteProperty -Name "API_Token" -Value $token -Force
    Save-Config $config
    Write-Host "API Token 已保存" -ForegroundColor Green
}

function Set-Domain {
    $config = Read-Config
    if (-not $config) { $config = New-Object PSObject }

    $ipv4 = Get-PublicIPv4
    if ($ipv4) {
        Write-Host "检测到公网 IPv4: $ipv4" -ForegroundColor Green
        $input = Read-Host "请输入要解析的 IPv4 域名（多个用逗号分隔，直接回车跳过）"
        if (-not [string]::IsNullOrEmpty($input)) {
            $domains = $input -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $config | Add-Member -MemberType NoteProperty -Name "Domains" -Value $domains -Force
            Write-Host "IPv4 域名: $($domains -join ', ')" -ForegroundColor Green
        }
    } else {
        Write-Host "未检测到 IPv4 地址，跳过 IPv4 域名设置" -ForegroundColor Yellow
    }

    $ipv6 = Get-PublicIPv6
    if ($ipv6) {
        Write-Host "检测到公网 IPv6: $ipv6" -ForegroundColor Green
        $yn = Read-Host "是否开启 IPv6 解析？(y/n)"
        if ($yn -eq 'y') {
            $config | Add-Member -MemberType NoteProperty -Name "ipv6_set" -Value "true" -Force
            $input = Read-Host "请输入要解析的 IPv6 域名（多个用逗号分隔，直接回车跳过）"
            if (-not [string]::IsNullOrEmpty($input)) {
                $domainsv6 = $input -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                $config | Add-Member -MemberType NoteProperty -Name "Domainsv6" -Value $domainsv6 -Force
                Write-Host "IPv6 域名: $($domainsv6 -join ', ')" -ForegroundColor Green
            }
        } else {
            $config | Add-Member -MemberType NoteProperty -Name "ipv6_set" -Value "false" -Force
        }
    } else {
        Write-Host "未检测到 IPv6 地址，跳过 IPv6 域名设置" -ForegroundColor Yellow
        $config | Add-Member -MemberType NoteProperty -Name "ipv6_set" -Value "false" -Force
    }

    Save-Config $config
}

function Set-TelegramSettings {
    Write-Host "`n========== Telegram 通知配置 ==========" -ForegroundColor Cyan
    $token = Read-Host "请输入 Telegram Bot Token（直接回车跳过）"
    if ([string]::IsNullOrEmpty($token)) { Write-Host "已跳过 Telegram 配置"; return }

    $chatId = Read-Host "请输入 Telegram Chat ID"
    if ([string]::IsNullOrEmpty($chatId)) { Write-Host "已跳过 Telegram 配置"; return }

    $config = Read-Config
    if (-not $config) { $config = New-Object PSObject }
    $config | Add-Member -MemberType NoteProperty -Name "Telegram_Bot_Token" -Value $token -Force
    $config | Add-Member -MemberType NoteProperty -Name "Telegram_Chat_ID" -Value $chatId -Force
    Save-Config $config
    Write-Host "Telegram 配置已保存" -ForegroundColor Green
}

function Set-FeishuSettings {
    Write-Host "`n========== 飞书通知配置 ==========" -ForegroundColor Cyan
    $webhook = Read-Host "请输入飞书 Webhook 地址（直接回车跳过）"
    if ([string]::IsNullOrEmpty($webhook)) { Write-Host "已跳过飞书配置"; return }

    $secret = Read-Host "请输入飞书签名密钥 Secret（如未启用签名校验直接回车）"

    $config = Read-Config
    if (-not $config) { $config = New-Object PSObject }
    $config | Add-Member -MemberType NoteProperty -Name "Feishu_Webhook" -Value $webhook -Force
    $config | Add-Member -MemberType NoteProperty -Name "Feishu_Secret" -Value $secret -Force
    Save-Config $config
    Write-Host "飞书配置已保存" -ForegroundColor Green
}

# ===================== 定时任务管理 =====================

function Install-ScheduledDdns {
    $taskName = "CloudflareDDNS"

    # 生成运行时脚本
    $runContent = @"
`$ConfigPath = Join-Path `$env:USERPROFILE ".ddns\config.json"

function Get-PublicIPv4 {
    `$urls = @("https://api.ipify.org", "https://ip.sb", "https://ipv4.icanhazip.com")
    foreach (`$url in `$urls) {
        try { `$ip = (Invoke-RestMethod -Uri `$url -TimeoutSec 5).Trim(); if (`$ip -match '^(\d{1,3}\.){3}\d{1,3}$') { return `$ip } } catch {}
    }
    return `$null
}

function Get-PublicIPv6 {
    `$urls = @("https://api6.ipify.org", "https://ip.sb")
    foreach (`$url in `$urls) {
        try { `$result = Invoke-RestMethod -Uri `$url -TimeoutSec 5; `$ip = `$result.Trim(); if (`$ip -match '^([0-9a-fA-F]{1,4}:){1,}[0-9a-fA-F]{0,4}') { return `$ip } } catch {}
    }
    return `$null
}

function Get-CfZoneId {
    param([string]`$Domain, [string]`$Token)
    try {
        `$headers = @{ "Authorization" = "Bearer `$Token"; "Content-Type" = "application/json" }
        `$resp = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones" -Headers `$headers -TimeoutSec 10
        if (-not `$resp.success) { return `$null }
        `$sorted = `$resp.result | Sort-Object { `$_.name.Length } -Descending
        foreach (`$zone in `$sorted) {
            if (`$Domain -eq `$zone.name -or `$Domain.EndsWith("." + `$zone.name)) { return `$zone.id }
        }
    } catch {}
    return `$null
}

function Get-CfDnsRecordId {
    param([string]`$ZoneId, [string]`$Type, [string]`$Name, [string]`$Token)
    try {
        `$headers = @{ "Authorization" = "Bearer `$Token"; "Content-Type" = "application/json" }
        `$uri = "https://api.cloudflare.com/client/v4/zones/`$ZoneId/dns_records?type=`$Type&name=`$Name"
        `$resp = Invoke-RestMethod -Uri `$uri -Headers `$headers -TimeoutSec 10
        if (`$resp.success -and `$resp.result.Count -gt 0) { return `$resp.result[0].id }
    } catch {}
    return `$null
}

function Update-CfDnsRecord {
    param([string]`$ZoneId, [string]`$RecordId, [string]`$Type, [string]`$Name, [string]`$Content, [string]`$Token)
    try {
        `$headers = @{ "Authorization" = "Bearer `$Token"; "Content-Type" = "application/json" }
        `$body = @{ type = `$Type; name = `$Name; content = `$Content } | ConvertTo-Json
        `$uri = "https://api.cloudflare.com/client/v4/zones/`$ZoneId/dns_records/`$RecordId"
        `$resp = Invoke-RestMethod -Uri `$uri -Method PUT -Headers `$headers -Body `$body -TimeoutSec 10
        return `$resp.success
    } catch { return `$false }
}

function Send-Telegram {
    param([string]`$BotToken, [string]`$ChatId, [string]`$Message)
    try {
        `$uri = "https://api.telegram.org/bot`$BotToken/sendMessage"
        `$body = @{ chat_id = `$ChatId; text = `$Message } | ConvertTo-Json
        Invoke-RestMethod -Uri `$uri -Method POST -Headers @{"Content-Type"="application/json"} -Body `$body -TimeoutSec 10 | Out-Null
    } catch {}
}

function Send-Feishu {
    param([string]`$Webhook, [string]`$Secret, [string]`$Message)
    try {
        `$body = @{ msg_type = "text"; content = @{ text = `$Message } }
        if (-not [string]::IsNullOrEmpty(`$Secret)) {
            `$timestamp = [Math]::Floor([DateTime]::UtcNow.Subtract([DateTime]"1970-01-01").TotalSeconds).ToString()
            `$signString = "`$timestamp`n`$Secret"
            `$hmac = New-Object System.Security.Cryptography.HMACSHA256
            `$hmac.Key = [Text.Encoding]::UTF8.GetBytes(`$Secret)
            `$hash = `$hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes(`$signString))
            `$body.timestamp = `$timestamp
            `$body.sign = [Convert]::ToBase64String(`$hash)
        }
        Invoke-RestMethod -Uri `$Webhook -Method POST -Headers @{"Content-Type"="application/json"} -Body (`$body | ConvertTo-Json) -TimeoutSec 10 | Out-Null
    } catch {}
}

if (-not (Test-Path `$ConfigPath)) { exit }
`$config = Get-Content `$ConfigPath -Raw | ConvertFrom-Json
if (-not `$config -or [string]::IsNullOrEmpty(`$config.API_Token)) { exit }

`$newIPv4 = Get-PublicIPv4
`$newIPv6 = `$null
if (`$config.ipv6_set -eq "true") { `$newIPv6 = Get-PublicIPv6 }

`$oldIPv4 = `$config.Public_IPv4
`$oldIPv6 = `$config.Public_IPv6
`$changed = `$false

if (`$newIPv4 -and `$config.Domains -and `$config.Domains.Count -gt 0) {
    foreach (`$domain in `$config.Domains) {
        `$zoneId = Get-CfZoneId -Domain `$domain -Token `$config.API_Token
        if (-not `$zoneId) { continue }
        `$recordId = Get-CfDnsRecordId -ZoneId `$zoneId -Type "A" -Name `$domain -Token `$config.API_Token
        if (-not `$recordId) { continue }
        Update-CfDnsRecord -ZoneId `$zoneId -RecordId `$recordId -Type "A" -Name `$domain -Content `$newIPv4 -Token `$config.API_Token | Out-Null
    }
    if (`$newIPv4 -ne `$oldIPv4) { `$changed = `$true; `$config.Public_IPv4 = `$newIPv4 }
}

if (`$config.ipv6_set -eq "true" -and `$newIPv6 -and `$config.Domainsv6 -and `$config.Domainsv6.Count -gt 0) {
    foreach (`$domain in `$config.Domainsv6) {
        `$zoneId = Get-CfZoneId -Domain `$domain -Token `$config.API_Token
        if (-not `$zoneId) { continue }
        `$recordId = Get-CfDnsRecordId -ZoneId `$zoneId -Type "AAAA" -Name `$domain -Token `$config.API_Token
        if (-not `$recordId) { continue }
        Update-CfDnsRecord -ZoneId `$zoneId -RecordId `$recordId -Type "AAAA" -Name `$domain -Content `$newIPv6 -Token `$config.API_Token | Out-Null
    }
    if (`$newIPv6 -ne `$oldIPv6) { `$changed = `$true; `$config.Public_IPv6 = `$newIPv6 }
}

if (`$changed) {
    `$parts = @()
    if (`$config.Domains) { `$parts += (`$config.Domains -join " ") }
    if (`$newIPv4 -and `$newIPv4 -ne `$oldIPv4) { `$parts += "IPv4更新 `$oldIPv4 -> `$newIPv4" }
    if (`$config.ipv6_set -and `$newIPv6 -and `$newIPv6 -ne `$oldIPv6) {
        if (`$config.Domainsv6 -and (`$config.Domains -join "") -ne (`$config.Domainsv6 -join "")) { `$parts += (`$config.Domainsv6 -join " ") }
        `$parts += "IPv6更新 `$oldIPv6 -> `$newIPv6"
    }
    `$msg = `$parts -join " 。"
    if (`$config.Telegram_Bot_Token -and `$config.Telegram_Chat_ID) { Send-Telegram -BotToken `$config.Telegram_Bot_Token -ChatId `$config.Telegram_Chat_ID -Message `$msg }
    if (`$config.Feishu_Webhook) { Send-Feishu -Webhook `$config.Feishu_Webhook -Secret `$config.Feishu_Secret -Message `$msg }
}

`$config | ConvertTo-Json -Depth 3 | Set-Content `$ConfigPath -Encoding UTF8
"@

    $dir = Split-Path $RunScriptPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $runContent | Set-Content $RunScriptPath -Encoding UTF8

    # 创建计划任务
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$RunScriptPath`""
    $trigger1 = New-ScheduledTaskTrigger -Daily -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)
    $trigger2 = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigger1, $trigger2) -Principal $principal -Force
        Write-Host "`n计划任务已创建：" -ForegroundColor Green
        Write-Host "  任务名称: $taskName"
        Write-Host "  触发器1: 每 5 分钟运行一次"
        Write-Host "  触发器2: 开机时运行"
        Write-Host "`n可以在任务计划程序库中查看和管理" -ForegroundColor Cyan
    } catch {
        Write-Error "创建计划任务失败: $_"
        Write-Host "请尝试以管理员身份运行 PowerShell" -ForegroundColor Yellow
    }
}

function Remove-ScheduledDdns {
    $taskName = "CloudflareDDNS"
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "计划任务已删除" -ForegroundColor Green

        if (Test-Path $RunScriptPath) { Remove-Item $RunScriptPath -Force }
    } catch {
        Write-Error "删除计划任务失败: $_"
    }
}

# ===================== 菜单 =====================

function Show-Menu {
    Clear-Host
    Write-Host "######################################" -ForegroundColor Green
    Write-Host "#   Cloudflare DDNS (Windows版)     #" -ForegroundColor Green
    Write-Host "#                                    #" -ForegroundColor Green
    Write-Host "######################################" -ForegroundColor Green
    Write-Host ""

    $config = Read-Config
    if ($config -and $config.API_Token) {
        Write-Host "[信息] DDNS 已配置" -ForegroundColor Green
    } else {
        Write-Host "[提示] DDNS 未配置，请首先配置 Cloudflare API Token" -ForegroundColor Yellow
    }

    Write-Host "`n请选择一个选项："
    Write-Host "  " -NoNewline; Write-Host "0" -ForegroundColor Green -NoNewline; Write-Host "：退出"
    Write-Host "  " -NoNewline; Write-Host "1" -ForegroundColor Green -NoNewline; Write-Host "：立即执行 DDNS 更新"
    Write-Host "  " -NoNewline; Write-Host "2" -ForegroundColor Green -NoNewline; Write-Host "：配置 Cloudflare API Token"
    Write-Host "  " -NoNewline; Write-Host "3" -ForegroundColor Green -NoNewline; Write-Host "：配置要解析的域名"
    Write-Host "  " -NoNewline; Write-Host "4" -ForegroundColor Green -NoNewline; Write-Host "：配置 Telegram 通知"
    Write-Host "  " -NoNewline; Write-Host "5" -ForegroundColor Green -NoNewline; Write-Host "：配置飞书通知"
    Write-Host "  " -NoNewline; Write-Host "6" -ForegroundColor Green -NoNewline; Write-Host "：安装计划任务（每5分钟运行 + 开机自启）"
    Write-Host "  " -NoNewline; Write-Host "7" -ForegroundColor Green -NoNewline; Write-Host "：卸载计划任务"

    $opt = Read-Host "`n选项"
    switch ($opt) {
        "0" { exit }
        "1" { Invoke-DdnsUpdate; pause }
        "2" { Set-CloudflareApi; pause }
        "3" { Set-Domain; pause }
        "4" { Set-TelegramSettings; pause }
        "5" { Set-FeishuSettings; pause }
        "6" { Install-ScheduledDdns; pause }
        "7" { Remove-ScheduledDdns; pause }
        default { Show-Menu }
    }
    Show-Menu
}

# ===================== 入口 =====================

if ($Run) {
    Invoke-DdnsUpdate
    exit
}

if ($Install) {
    Install-ScheduledDdns
    exit
}

if ($Uninstall) {
    Remove-ScheduledDdns
    exit
}

$config = Read-Config
if (-not $config -or [string]::IsNullOrEmpty($config.API_Token)) {
    Clear-Host
    Write-Host "========== 首次运行，开始配置 DDNS ==========" -ForegroundColor Cyan
    Set-CloudflareApi
    Set-Domain

    $yn = Read-Host "`n是否配置 Telegram 通知？(y/n)"
    if ($yn -eq 'y') { Set-TelegramSettings }

    $yn = Read-Host "是否配置飞书通知？(y/n)"
    if ($yn -eq 'y') { Set-FeishuSettings }

    $yn = Read-Host "`n是否安装计划任务（每5分钟运行 + 开机自启）？(y/n)"
    if ($yn -eq 'y') { Install-ScheduledDdns }

    Write-Host "`n配置完成！" -ForegroundColor Green
    Write-Host "提示：以后运行 ddns.ps1 可呼出菜单" -ForegroundColor Cyan
    Start-Sleep -Seconds 2
}

Show-Menu
