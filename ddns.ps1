param(
    [switch]$Run,
    [switch]$Install,
    [switch]$Uninstall
)

$ConfigPath = Join-Path $env:USERPROFILE ".ddns\config.json"
$LogPath = Join-Path $env:USERPROFILE ".ddns\ddns.log"
$ServiceName = "CloudflareDDNS"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$time][$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}

function Write-Info { Write-Log @args -Level "INFO" }
function Write-Error { Write-Log @args -Level "ERROR" }
function Write-Warn { Write-Log @args -Level "WARN" }

function Read-Config {
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
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
            $ip = (Invoke-RestMethod -Uri $url -TimeoutSec 5).Trim()
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
        Invoke-RestMethod -Uri $uri -Method POST -Headers @{"Content-Type"="application/json"} -Body $body -TimeoutSec 10 | Out-Null
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
            $body.timestamp = $timestamp
            $body.sign = [Convert]::ToBase64String($hash)
        }

        Invoke-RestMethod -Uri $Webhook -Method POST -Headers @{"Content-Type"="application/json"} -Body ($body | ConvertTo-Json) -TimeoutSec 10 | Out-Null
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
    Add-Content -Path $LogPath -Value "===== DDNS 更新开始 ====="
    $config = Read-Config
    if (-not $config -or [string]::IsNullOrEmpty($config.API_Token)) {
        Add-Content -Path $LogPath -Value "[ERROR] 配置文件不存在或未配置 API Token"
        return
    }

    $newIPv4 = Get-PublicIPv4
    $newIPv6 = $null
    if ($config.ipv6_set -eq "true") { $newIPv6 = Get-PublicIPv6 }

    Add-Content -Path $LogPath -Value "[INFO] 当前公网 IPv4: $newIPv4"
    if ($newIPv6) { Add-Content -Path $LogPath -Value "[INFO] 当前公网 IPv6: $newIPv6" }

    $oldIPv4 = $config.Public_IPv4
    $oldIPv6 = $config.Public_IPv6
    $changed = $false

    if ($newIPv4 -and $config.Domains -and $config.Domains.Count -gt 0) {
        foreach ($domain in $config.Domains) {
            $zoneId = Get-CfZoneId -Domain $domain -Token $config.API_Token
            if (-not $zoneId) { Add-Content -Path $LogPath -Value "[ERROR] 未找到 $domain 对应的 Zone"; continue }

            $recordId = Get-CfDnsRecordId -ZoneId $zoneId -Type "A" -Name $domain -Token $config.API_Token
            if (-not $recordId) { Add-Content -Path $LogPath -Value "[WARN] 未找到 $domain 的 A 记录"; continue }

            $ok = Update-CfDnsRecord -ZoneId $zoneId -RecordId $recordId -Type "A" -Name $domain -Content $newIPv4 -Token $config.API_Token
            if ($ok) { Add-Content -Path $LogPath -Value "[INFO] $domain -> $newIPv4 更新成功" } else { Add-Content -Path $LogPath -Value "[ERROR] $domain -> $newIPv4 更新失败" }
        }
        if ($newIPv4 -ne $oldIPv4) { $changed = $true; $config.Public_IPv4 = $newIPv4 }
    }

    if ($config.ipv6_set -eq "true" -and $newIPv6 -and $config.Domainsv6 -and $config.Domainsv6.Count -gt 0) {
        foreach ($domain in $config.Domainsv6) {
            $zoneId = Get-CfZoneId -Domain $domain -Token $config.API_Token
            if (-not $zoneId) { Add-Content -Path $LogPath -Value "[ERROR] 未找到 $domain 对应的 Zone"; continue }

            $recordId = Get-CfDnsRecordId -ZoneId $zoneId -Type "AAAA" -Name $domain -Token $config.API_Token
            if (-not $recordId) { Add-Content -Path $LogPath -Value "[WARN] 未找到 $domain 的 AAAA 记录"; continue }

            $ok = Update-CfDnsRecord -ZoneId $zoneId -RecordId $recordId -Type "AAAA" -Name $domain -Content $newIPv6 -Token $config.API_Token
            if ($ok) { Add-Content -Path $LogPath -Value "[INFO] $domain -> $newIPv6 更新成功" } else { Add-Content -Path $LogPath -Value "[ERROR] $domain -> $newIPv6 更新失败" }
        }
        if ($newIPv6 -ne $oldIPv6) { $changed = $true; $config.Public_IPv6 = $newIPv6 }
    }

    if ($changed) {
        $msg = Build-NotifyMessage -Config $config -OldIPv4 $oldIPv4 -NewIPv4 $newIPv4 -OldIPv6 $oldIPv6 -NewIPv6 $newIPv6

        if ($config.Telegram_Bot_Token -and $config.Telegram_Chat_ID) {
            Send-Telegram -BotToken $config.Telegram_Bot_Token -ChatId $config.Telegram_Chat_ID -Message $msg
            Add-Content -Path $LogPath -Value "[INFO] Telegram 通知已发送"
        }
        if ($config.Feishu_Webhook) {
            Send-Feishu -Webhook $config.Feishu_Webhook -Secret $config.Feishu_Secret -Message $msg
            Add-Content -Path $LogPath -Value "[INFO] 飞书通知已发送"
        }
    }

    $config | ConvertTo-Json -Depth 3 | Set-Content $ConfigPath -Encoding UTF8
    Add-Content -Path $LogPath -Value "===== DDNS 更新完成 ====="
}

# ===================== 交互配置 =====================

function Set-CloudflareApi {
    Write-Host "`n========== Cloudflare API 配置 ==========" -ForegroundColor Cyan
    $token = Read-Host "请输入您的 Cloudflare API Token"
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

# ===================== NSSM 服务管理 =====================

function Test-NssmInstalled {
    try {
        $nssm = Get-Command nssm.exe -ErrorAction SilentlyContinue
        if ($nssm) { return $true }
        $nssm = Get-Item "${env:ProgramFiles}\nssm\nssm.exe" -ErrorAction SilentlyContinue
        if ($nssm) { return $true }
        $nssm = Get-Item "${env:ProgramFiles(x86)}\nssm\nssm.exe" -ErrorAction SilentlyContinue
        if ($nssm) { return $true }
        return $false
    } catch {
        return $false
    }
}

function Install-DdnsService {
    if (-not (Test-NssmInstalled)) {
        Write-Error "未检测到 nssm.exe，请先安装 NSSM (https://nssm.cc/download)"
        Write-Host "安装后请确保 nssm.exe 在 PATH 环境变量中" -ForegroundColor Yellow
        return
    }

    $psPath = (Get-Command powershell.exe).Source
    $scriptPath = $MyInvocation.MyCommand.Path
    if ([string]::IsNullOrEmpty($scriptPath)) {
        $scriptPath = "$env:USERPROFILE\ddns.ps1"
    }

    Write-Host "正在安装 Windows 服务..." -ForegroundColor Cyan

    # 删除已存在的服务
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        nssm.exe stop $ServiceName confirm
        nssm.exe remove $ServiceName confirm
        Start-Sleep -Seconds 2
    }

    # 注册服务
    nssm.exe install $ServiceName $psPath "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Run"
    Start-Sleep -Seconds 1

    # 设置服务参数 - 每5分钟循环运行
    nssm.exe set $ServiceName AppParameters "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Run"
    nssm.exe set $ServiceName AppStdout "$env:USERPROFILE\.ddns\nssm_stdout.log" 2>$null
    nssm.exe set $ServiceName AppStderr "$env:USERPROFILE\.ddns\nssm_stderr.log" 2>$null
    nssm.exe set $ServiceName AppRotateFiles 1
    nssm.exe set $ServiceName AppRotateOnline 1
    nssm.exe set $ServiceName AppRotateSeconds 86400
    nssm.exe set $ServiceName Start SERVICE_AUTO_START
    nssm.exe set $ServiceName ObjectName LocalSystem

    Start-Sleep -Seconds 1
    nssm.exe start $ServiceName

    Write-Host "`n服务已创建并启动！" -ForegroundColor Green
    Write-Host "  服务名称: $ServiceName" -ForegroundColor Cyan
    Write-Host "  services.msc 中可查看和管理" -ForegroundColor Cyan
    Write-Host "  日志文件: $env:USERPROFILE\.ddns\ddns.log" -ForegroundColor Cyan
}

function Remove-DdnsService {
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "服务 $ServiceName 不存在" -ForegroundColor Yellow
        return
    }

    Write-Host "正在卸载服务..." -ForegroundColor Cyan
    nssm.exe stop $ServiceName confirm
    Start-Sleep -Seconds 2
    nssm.exe remove $ServiceName confirm
    Write-Host "服务 $ServiceName 已卸载" -ForegroundColor Green
}

# ===================== 菜单 =====================

function Show-Menu {
    Clear-Host
    Write-Host "######################################" -ForegroundColor Green
    Write-Host "#   Cloudflare DDNS (Windows 版)     #" -ForegroundColor Green
    Write-Host "######################################" -ForegroundColor Green
    Write-Host ""

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Host "[信息] DDNS 服务: 已安装并运行中" -ForegroundColor Green
        $config = Read-Config
        if ($config -and $config.API_Token) { Write-Host "[信息] API Token: 已配置" -ForegroundColor Green }
        else { Write-Host "[提示] API Token: 未配置" -ForegroundColor Yellow }
    } elseif ($service) {
        Write-Host "[提示] DDNS 服务: 已安装但未运行" -ForegroundColor Yellow
    } else {
        Write-Host "[提示] DDNS 服务: 未安装" -ForegroundColor Yellow
    }

    Write-Host "`n请选择一个选项："
    Write-Host "  " -NoNewline; Write-Host "0" -ForegroundColor Green -NoNewline; Write-Host "：退出"
    Write-Host "  " -NoNewline; Write-Host "1" -ForegroundColor Green -NoNewline; Write-Host "：立即执行 DDNS 更新"
    Write-Host "  " -NoNewline; Write-Host "2" -ForegroundColor Green -NoNewline; Write-Host "：配置 Cloudflare API Token"
    Write-Host "  " -NoNewline; Write-Host "3" -ForegroundColor Green -NoNewline; Write-Host "：配置要解析的域名"
    Write-Host "  " -NoNewline; Write-Host "4" -ForegroundColor Green -NoNewline; Write-Host "：配置 Telegram 通知"
    Write-Host "  " -NoNewline; Write-Host "5" -ForegroundColor Green -NoNewline; Write-Host "：配置飞书通知"
    Write-Host "  " -NoNewline; Write-Host "6" -ForegroundColor Green -NoNewline; Write-Host "：安装 NSSM 服务（开机自启 + 持续运行）"
    Write-Host "  " -NoNewline; Write-Host "7" -ForegroundColor Red -NoNewline; Write-Host "：卸载 NSSM 服务"

    $opt = Read-Host "`n选项"
    switch ($opt) {
        "0" { exit }
        "1" { Invoke-DdnsUpdate; pause }
        "2" { Set-CloudflareApi; pause }
        "3" { Set-Domain; pause }
        "4" { Set-TelegramSettings; pause }
        "5" { Set-FeishuSettings; pause }
        "6" { Install-DdnsService; pause }
        "7" { Remove-DdnsService; pause }
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
    Install-DdnsService
    exit
}

if ($Uninstall) {
    Remove-DdnsService
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

    $yn = Read-Host "`n是否安装 NSSM 服务（开机自启 + 持续运行）？(y/n)"
    if ($yn -eq 'y') { Install-DdnsService }

    Write-Host "`n配置完成！" -ForegroundColor Green
    Write-Host "提示：以后运行 ddns.ps1 可呼出菜单" -ForegroundColor Cyan
    Start-Sleep -Seconds 2
}

Show-Menu
