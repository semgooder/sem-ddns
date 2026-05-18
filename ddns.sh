Logo

复制

词搜找货

翻译

设置
#!/bin/bash

# 输出字体颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[0;33m"
NC="\033[0m"
GREEN_ground="\033[42;37m" # 全局绿色
RED_ground="\033[41;37m"   # 全局红色
Info="${GREEN}[信息]${NC}"
Error="${RED}[错误]${NC}"
Tip="${YELLOW}[提示]${NC}"

cop_info(){
clear
echo -e "${GREEN}######################################
#      ${RED}   DDNS 一键脚本 v2.3         ${GREEN}#
#             作者: ${YELLOW}末晨             ${GREEN}#
#       ${GREEN}https://blog.mochen.one      ${GREEN}#
######################################${NC}"
echo
}

# 检查系统是否为 Debian、Ubuntu 或 Alpine
if ! grep -qiE "debian|ubuntu|alpine" /etc/os-release; then
    echo -e "${RED}本脚本仅支持 Debian、Ubuntu 或 Alpine 系统，请在这些系统上运行。${NC}"
    exit 1
fi

# 检查是否为root用户
if [[ $(whoami) != "root" ]]; then
    echo -e "${Error}请以root身份执行该脚本！"
    exit 1
fi

# 检查是否安装 curl 和 GNU grep（仅 Alpine），如果没有安装，则安装它们
check_curl() {
    if ! command -v curl &>/dev/null; then
        echo -e "${YELLOW}未检测到 curl，正在安装 curl...${NC}"

        # 根据不同的系统类型选择安装命令
        if grep -qiE "debian|ubuntu" /etc/os-release; then
            apt update
            apt install -y curl
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Debian/Ubuntu 上安装 curl 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        elif grep -qiE "alpine" /etc/os-release; then
            apk update
            apk add curl
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Alpine 上安装 curl 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        fi
    fi

    # 仅在 Alpine 系统上检查是否为 GNU 版本的 grep，如果不是，则安装 GNU grep
    if grep -qiE "alpine" /etc/os-release; then
        if ! grep --version 2>/dev/null | grep -q "GNU"; then
            echo -e "${YELLOW}当前 grep 不是 GNU 版本，正在安装 GNU grep...${NC}"
            
            apk update
            apk add grep
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Alpine 上安装 GNU grep 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        else
            echo -e "${GREEN}GNU grep 已经安装。${NC}"
        fi
    fi

    # 检查是否安装 openssl（飞书签名校验需要）
    if ! command -v openssl &>/dev/null; then
        echo -e "${YELLOW}未检测到 openssl，正在安装 openssl...${NC}"

        if grep -qiE "debian|ubuntu" /etc/os-release; then
            apt update
            apt install -y openssl
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Debian/Ubuntu 上安装 openssl 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        elif grep -qiE "alpine" /etc/os-release; then
            apk update
            apk add openssl
            if [ $? -ne 0 ]; then
                echo -e "${RED}在 Alpine 上安装 openssl 失败，请手动安装后重新运行脚本。${NC}"
                exit 1
            fi
        fi
    fi
}

# 开始安装DDNS
install_ddns(){
    mkdir -p /etc/DDNS
    cat <<'EOF' > /etc/DDNS/DDNS
#!/bin/bash

source /etc/DDNS/.config

Old_Public_IPv4="$Old_Public_IPv4"
Old_Public_IPv6="$Old_Public_IPv6"

# =================== DNSPod 函数 ===================

dnspod_split_domain() {
    local full="$1"
    local parts_count=$(echo "$full" | awk -F'.' '{print NF}')
    if [ "$parts_count" -le 2 ]; then
        echo "$full|@"
    else
        local root=$(echo "$full" | awk -F'.' '{print $(NF-1)"."$NF}')
        local sub="${full%.$root}"
        echo "$root|$sub"
    fi
}

dnspod_api() {
    local action="$1"
    shift
    local data="login_token=${DNSPod_ID},${DNSPod_Token}&format=json"
    for pair in "$@"; do
        data="${data}&${pair}"
    done
    curl -s -X POST "https://dnsapi.cn${action}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "User-Agent: sem-ddns/1.0" \
        --data "$data"
}

dnspod_get_domain_id() {
    local domain="$1"
    local resp=$(dnspod_api "/Domain.List")
    echo "$resp" | grep -oP '"id":"\K[^"]*"' | head -1
}

dnspod_update() {
    local domain="$1" rtype="$2" value="$3"
    local split=$(dnspod_split_domain "$domain")
    local root="${split%%|*}"
    local sub="${split##*|}"

    # 获取域名 ID
    local list_resp=$(dnspod_api "/Domain.List")
    local pairs=$(echo "$list_resp" | grep -oP '"id":"[^"]*","name":"[^"]*"')
    local domain_id=""
    while IFS= read -r pair; do
        [ -z "$pair" ] && continue
        local curname=$(echo "$pair" | grep -oP '"name":"\K[^"]+')
        if [ "$curname" = "$root" ]; then
            domain_id=$(echo "$pair" | grep -oP '"id":"\K[^"]+')
            break
        fi
    done <<< "$pairs"
    [ -z "$domain_id" ] && echo "未找到 $root 的域名 ID" && return 1

    # 查找记录
    local record_resp=$(dnspod_api "/Record.List" "domain_id=${domain_id}" "sub_domain=${sub}")
    local record_id=$(echo "$record_resp" | grep -oP '"id":"\K[^"]*' | head -1)
    [ -z "$record_id" ] && echo "未找到 $domain 的 $rtype 记录" && return 1

    # 修改记录
    local mod_resp=$(dnspod_api "/Record.Modify" \
        "domain_id=${domain_id}" \
        "record_id=${record_id}" \
        "sub_domain=${sub}" \
        "record_type=${rtype}" \
        "record_line=默认" \
        "value=${value}")
    local code=$(echo "$mod_resp" | grep -oP '"code":"\K[^"]*')
    if [ "$code" = "1" ]; then
        echo "$domain -> $value 更新成功"
        return 0
    else
        echo "$domain -> $value 更新失败"
        return 1
    fi
}

# =================== Cloudflare 函数 ===================

get_zone_id() {
    local domain="$1"
    local response entry zid zname

    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
        -H "Authorization: Bearer $API_Token" \
        -H "Content-Type: application/json")

    echo "$response" | grep -oP '"id":"[^"]*","name":"[^"]*"' | while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        zid=$(echo "$entry" | grep -oP '"id":"\K[^"]+')
        zname=$(echo "$entry" | grep -oP '"name":"\K[^"]+')
        case ".$domain" in
            *".$zname") echo "$zid"; break ;;
        esac
    done | head -1
}

# =================== 更新分发 ===================

update_domain() {
    local domain="$1" rtype="$2" value="$3"
    if [ "$Provider" = "dnspod" ]; then
        dnspod_update "$domain" "$rtype" "$value"
    else
        local zone_id=$(get_zone_id "$domain")
        [ -z "$zone_id" ] && echo "未找到 $domain 对应的 Zone" && return 1

        local record_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$rtype&name=$domain" \
             -H "Authorization: Bearer $API_Token" \
             -H "Content-Type: application/json" \
             | grep -oP '"id":"\K[^"]+' | head -1)
        [ -z "$record_id" ] && echo "未找到 $domain 的 $rtype 记录" && return 1

        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
             -H "Authorization: Bearer $API_Token" \
             -H "Content-Type: application/json" \
             --data "{\"type\":\"$rtype\",\"name\":\"$domain\",\"content\":\"$value\"}" >/dev/null 2>&1 && \
             echo "$domain -> $value 更新成功" || echo "$domain -> $value 更新失败"
    fi
}

# =================== 执行更新 ===================

for Domain in "${Domains[@]}"; do
    update_domain "$Domain" "A" "$Public_IPv4"
done

if [ "$ipv6_set" = "true" ]; then
    for Domainv6 in "${Domainsv6[@]}"; do
        update_domain "$Domainv6" "AAAA" "$Public_IPv6"
    done
fi

# 发送Telegram通知
if [[ -n "$Telegram_Bot_Token" && -n "$Telegram_Chat_ID" && (("$Public_IPv4" != "$Old_Public_IPv4" && -n "$Public_IPv4") || ("$Public_IPv6" != "$Old_Public_IPv6" && -n "$Public_IPv6")) ]]; then
    send_telegram_notification
fi

# 发送飞书通知
if [[ -n "$Feishu_Webhook" && (("$Public_IPv4" != "$Old_Public_IPv4" && -n "$Public_IPv4") || ("$Public_IPv6" != "$Old_Public_IPv6" && -n "$Public_IPv6")) ]]; then
    send_feishu_notification
fi

sleep 3

if [[ -n "$Public_IPv4" && "$Public_IPv4" != "$Old_Public_IPv4" ]]; then
    sed -i "s/^Old_Public_IPv4=.*/Old_Public_IPv4=\"$Public_IPv4\"/" /etc/DDNS/.config
fi

if [[ -n "$Public_IPv6" && "$Public_IPv6" != "$Old_Public_IPv6" ]]; then
    sed -i "s/^Old_Public_IPv6=.*/Old_Public_IPv6=\"$Public_IPv6\"/" /etc/DDNS/.config
fi
EOF
    cat <<'EOF' > /etc/DDNS/.config
# DNS 服务商: cloudflare / dnspod
Provider="cloudflare"

# 多域名支持
Domains=("your_domain1.com" "your_domain2.com")     # 你要解析的IPv4域名数组
ipv6_set="setting"                                    # 开启 IPv6 解析
Domainsv6=("your_domainv6_1.com" "your_domainv6_2.com")  # 你要解析的IPv6域名数组

# Cloudflare 凭证
API_Token="your_api_token"                         # 你的 Cloudflare API 令牌

# DNSPod 凭证
DNSPod_ID=""
DNSPod_Token=""

# Telegram Bot Token 和 Chat ID
Telegram_Bot_Token=""
Telegram_Chat_ID=""

# 飞书 Webhook 地址
Feishu_Webhook=""
# 飞书签名密钥（如启用签名校验则填写，不填则不签名）
Feishu_Secret=""

# 获取公网IP地址
regex_pattern='^(eth|ens|eno|esp|enp)[0-9]+'

# 获取网络接口列表
InterFace=($(ip link show | awk -F': ' '{print $2}' | grep -E "$regex_pattern" | sed "s/@.*//g"))

Public_IPv4=""
Public_IPv6=""
Old_Public_IPv4=""
Old_Public_IPv6=""
ipv4Regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
ipv6Regex="^([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])$"

# 检查操作系统类型
if grep -qiE "debian|ubuntu" /etc/os-release; then
    # Debian/Ubuntu系统的IP获取方法
    for i in "${InterFace[@]}"; do
        # 尝试通过第一个接口获取 IPv4 地址
        ipv4=$(curl -s4 --max-time 3 --interface "$i" ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)

        # 如果第一个接口的 IPv4 地址获取失败，尝试备用接口
        if [[ -z "$ipv4" ]]; then
            ipv4=$(curl -s4 --max-time 3 --interface "$i" https://api.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
        fi

        # 验证获取到的 IPv4 地址是否是有效的 IP 地址
        if [[ -n "$ipv4" && "$ipv4" =~ $ipv4Regex ]]; then
            Public_IPv4="$ipv4"
        fi

        # 检查是否启用了 IPv6 解析
        if [[ "$ipv6_set" == "true" ]]; then
            # 尝试通过第一个接口获取 IPv6 地址
            ipv6=$(curl -s6 --max-time 3 --interface "$i" ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)

            # 如果第一个接口的 IPv6 地址获取失败，尝试备用接口
            if [[ -z "$ipv6" ]]; then
                ipv6=$(curl -s6 --max-time 3 --interface "$i" https://api6.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
            fi

            # 验证获取到的 IPv6 地址是否是有效的 IP 地址
            if [[ -n "$ipv6" && "$ipv6" =~ $ipv6Regex ]]; then
                Public_IPv6="$ipv6"
            fi
        fi
    done
else
    # Alpine系统的IP获取方法
    # 尝试获取 IPv4 地址
    ipv4=$(curl -s4 --max-time 3 ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)
    if [[ -z "$ipv4" ]]; then
        ipv4=$(curl -s4 --max-time 3 https://api.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
    fi

    # 验证获取到的 IPv4 地址是否是有效的 IP 地址
    if [[ -n "$ipv4" && "$ipv4" =~ $ipv4Regex ]]; then
        Public_IPv4="$ipv4"
    fi

    # 检查是否启用了 IPv6 解析
    if [[ "$ipv6_set" == "true" ]]; then
        # 尝试获取 IPv6 地址
        ipv6=$(curl -s6 --max-time 3 ip.sb -k | grep -E -v '^(2a09|104\.28)' || true)
        if [[ -z "$ipv6" ]]; then
            ipv6=$(curl -s6 --max-time 3 https://api6.ipify.org -k | grep -E -v '^(2a09|104\.28)' || true)
        fi

        # 验证获取到的 IPv6 地址是否是有效的 IP 地址
        if [[ -n "$ipv6" && "$ipv6" =~ $ipv6Regex ]]; then
            Public_IPv6="$ipv6"
        fi
    fi
fi

# 发送 Telegram 通知函数
send_telegram_notification() {
    local message=""

    # 遍历 Domains 数组，构建域名部分
    for domain in "${Domains[@]}"; do
        message+="$domain "
    done

    # 添加 IPv4 更新信息
    message+="IPv4更新 $Old_Public_IPv4 🔜 $Public_IPv4 。"

    # 如果 ipv6_set 为 true，则添加 IPv6 更新信息
    if [ "$ipv6_set" == "true" ]; then
        # 检查 Domains 和 Domainsv6 是否相同
        if [ "${Domains[*]}" != "${Domainsv6[*]}" ]; then
            # 遍历 Domainsv6 数组，构建 IPv6 域名部分
            for domainv6 in "${Domainsv6[@]}"; do
                message+="$domainv6 "
            done
        fi

        # 添加 IPv6 更新信息
        message+="IPv6更新 $Old_Public_IPv6 🔜 $Public_IPv6 。"
    fi

    # 发送通知
    curl -s -X POST "https://api.telegram.org/bot$Telegram_Bot_Token/sendMessage" \
        -d "chat_id=$Telegram_Chat_ID" \
        -d "text=$message"
}

# 发送飞书通知函数
send_feishu_notification() {
    local message=""
    local body=""

    for domain in "${Domains[@]}"; do
        message+="$domain "
    done

    message+="IPv4更新 $Old_Public_IPv4 -> $Public_IPv4 。"

    if [ "$ipv6_set" == "true" ]; then
        if [ "${Domains[*]}" != "${Domainsv6[*]}" ]; then
            for domainv6 in "${Domainsv6[@]}"; do
                message+="$domainv6 "
            done
        fi
        message+="IPv6更新 $Old_Public_IPv6 -> $Public_IPv6 。"
    fi

    body="{\"msg_type\":\"text\",\"content\":{\"text\":\"$message\"}"

    if [ -n "$Feishu_Secret" ]; then
        local timestamp=$(date +%s)
        local sign=$(echo -n "${timestamp}\n${Feishu_Secret}" | openssl dgst -sha256 -hmac "$Feishu_Secret" -binary | openssl base64 -A)
        body="${body},\"timestamp\":\"${timestamp}\",\"sign\":\"${sign}\""
    fi

    body="${body}}"

    curl -s -X POST "$Feishu_Webhook" \
        -H "Content-Type: application/json" \
        --data "$body" >/dev/null 2>&1
}

EOF
    chmod +x /etc/DDNS/DDNS && chmod +x /etc/DDNS/.config
    echo -e "${Info}DDNS 安装完成！"
    echo
}

# 检查 DDNS 状态
check_ddns_status() {
    if grep -qiE "alpine" /etc/os-release; then
        # 检查 cron 任务是否存在
        if crontab -l | grep -q "/bin/bash /etc/DDNS/DDNS"; then
            ddns_status=running
        else
            ddns_status=dead
        fi
    else
        # 在 Debian/Ubuntu 上检查 systemd timer 状态
        if [[ -f "/etc/systemd/system/ddns.timer" ]]; then
            STatus=$(systemctl status ddns.timer | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
            if [[ $STatus =~ "waiting" || $STatus =~ "running" ]]; then
                ddns_status=running
            else
                ddns_status=dead
            fi
        else
            ddns_status=not_installed
        fi
    fi
}

# 后续操作
go_ahead(){
    echo -e "${Tip}选择一个选项：
  ${GREEN}0${NC}：退出
  ${GREEN}1${NC}：重启 DDNS
  ${GREEN}2${NC}：停止 DDNS
  ${GREEN}3${NC}：${RED}卸载 DDNS${NC}
  ${GREEN}4${NC}：修改要解析的域名
  ${GREEN}5${NC}：配置 DNS 服务商和凭证
  ${GREEN}6${NC}：配置 Telegram 通知
  ${GREEN}7${NC}：更改 DDNS 运行时间
  ${GREEN}8${NC}：配置飞书通知"
    echo
    read -p "选项: " option
    until [[ "$option" =~ ^[0-8]$ ]]; do
        echo -e "${Error}请输入正确的数字 [0-8]"
        echo
        exit 1
    done
    case "$option" in
        0)
            exit 1
        ;;
        1)
            restart_ddns
        ;;
        2)
            stop_ddns
        ;;
        3)
            if grep -qiE "alpine" /etc/os-release; then
                stop_ddns
                rm -rf /etc/DDNS /usr/bin/ddns
            else
                systemctl stop ddns.service >/dev/null 2>&1
                systemctl stop ddns.timer >/dev/null 2>&1
                rm -rf /etc/systemd/system/ddns.service /etc/systemd/system/ddns.timer /etc/DDNS /usr/bin/ddns
            fi
            echo -e "${Info}DDNS 已卸载！"
            echo
        ;;
        4)
            set_domain
            restart_ddns
            sleep 2
            check_ddns_install
        ;;
        5)
            set_dns_provider
            if grep -qiE "alpine" /etc/os-release; then
                restart_ddns
                sleep 2
            else
                if [ ! -f "/etc/systemd/system/ddns.service" ] || [ ! -f "/etc/systemd/system/ddns.timer" ]; then
                    run_ddns
                    sleep 2
                else
                    restart_ddns
                    sleep 2
                fi
            fi
            check_ddns_install
        ;;
        6)
            set_telegram_settings
            check_ddns_install
        ;;
        7)
            set_ddns_run_interval
            sleep 2
            check_ddns_install
        ;;
        8)
            set_feishu_settings
            check_ddns_install
        ;;
    esac
}

# 设置 DNS 服务商和凭证
set_dns_provider(){
    echo -e "${Tip}选择 DNS 服务商："
    echo "  ${GREEN}1${NC}：Cloudflare（API Token）"
    echo "  ${GREEN}2${NC}：DNSPod（独立版，ID + Token）"
    read -rp "请选择 [1/2] (默认 1): " provider_choice

    if [ "$provider_choice" = "2" ]; then
        sed -i 's|^#\?Provider=".*"|Provider="dnspod"|g' /etc/DDNS/.config

        echo -e "${Tip}开始配置 DNSPod API..."
        echo
        echo -e "${YELLOW}请在 DNSPod 控制台 -> 安全设置 -> API 密钥 中获取${NC}"
        read -rp "DNSPod ID: " Dp_Id
        if [ -z "$Dp_Id" ]; then
            echo -e "${Error}未输入 ID，无法执行操作！"
            exit 1
        fi
        read -rp "DNSPod Token: " Dp_Token
        if [ -z "$Dp_Token" ]; then
            echo -e "${Error}未输入 Token，无法执行操作！"
            exit 1
        fi

        sed -i 's|^#\?DNSPod_ID=".*"|DNSPod_ID="'"${Dp_Id}"'"|g' /etc/DDNS/.config
        sed -i 's|^#\?DNSPod_Token=".*"|DNSPod_Token="'"${Dp_Token}"'"|g' /etc/DDNS/.config
        echo -e "${Info}DNSPod 配置已保存"
    else
        sed -i 's|^#\?Provider=".*"|Provider="cloudflare"|g' /etc/DDNS/.config

        echo -e "${Tip}开始配置 CloudFlare API..."
        echo
        echo -e "${Tip}请输入您的 Cloudflare API 令牌（API Token）"
        echo -e "${YELLOW}请在 Cloudflare 控制面板 -> 我的资料 -> API 令牌 中创建或获取${NC}"
        read -rp "API Token: " Api_Token
        if [ -z "$Api_Token" ]; then
            echo -e "${Error}未输入 API Token，无法执行操作！"
            exit 1
        fi
        echo -e "${Info}你的 API Token：${RED_ground}${Api_Token}${NC}"
        echo
        sed -i 's|^#\?API_Token=".*"|API_Token="'"${Api_Token}"'"|g' /etc/DDNS/.config
        echo -e "${Info}Cloudflare 配置已保存"
    fi
    echo
}

# 设置解析的域名
set_domain() {
    # 检查是否有IPv4
    ipv4_check=$(curl -s ip.sb -4)
    if [ -n "$ipv4_check" ]; then
        echo -e "${Info}检测到IPv4地址: ${ipv4_check}"
        echo -e "${Tip}请输入您要解析的IPv4域名（可解析多个域名，使用逗号分隔） (或按回车跳过)"
        read -rp "IPv4域名: " Domain_input
        if [ -z "$Domain_input" ]; then
            echo -e "${Info}跳过IPv4域名设置。"
        else
            # 替换中文逗号为英文逗号
            Domain_input="${Domain_input//，/,}"
            IFS=',' read -ra Domains <<< "$Domain_input"
            echo -e "${Info}你输入的IPv4域名为: ${RED_ground}${Domains[*]}${NC}"
            echo
            # 更新 .config 文件中的 IPv4 域名数组，保持原位置修改
            sed -i '/^Domains=/c\Domains=('"${Domains[*]}"')' /etc/DDNS/.config
        fi
    else
        echo -e "${Info}未检测到IPv4地址，跳过IPv4域名设置。"
        echo
    fi

    # 检查是否有IPv6
    ipv6_check=$(curl -s ip.sb -6)
    if [ -n "$ipv6_check" ]; then
        echo -e "${Info}检测到IPv6地址: ${ipv6_check}"

        # 检查是否开启 IPv6 解析
        while true; do
            echo -e "${Tip}是否开启 IPv6 解析？(y/n)"
            read -rp "选择: " enable_ipv6

            if [[ "$enable_ipv6" =~ ^[Yy]$ ]]; then
                ipv6_set="true"
                # 更新 .config 文件中的 ipv6_set 为 true
                sed -i 's/^#\?ipv6_set=".*"/ipv6_set="true"/g' /etc/DDNS/.config

                echo -e "${Tip}请输入您要解析的IPv6域名（可解析多个域名，使用逗号分隔） (或按回车跳过)"
                read -rp "IPv6域名: " Domainv6_input

                if [ -z "$Domainv6_input" ]; then
                    echo -e "${Info}跳过IPv6域名设置。"
                    echo
                else
                    # 替换中文逗号为英文逗号
                    Domainv6_input="${Domainv6_input//，/,}"
                    IFS=',' read -ra Domainsv6 <<< "$Domainv6_input"
                    echo -e "${Info}你输入的IPv6域名为: ${RED_ground}${Domainsv6[*]}${NC}"
                    echo
                    # 更新 .config 文件中的 IPv6 域名数组，保持原位置修改
                    sed -i '/^Domainsv6=/c\Domainsv6=('"${Domainsv6[*]}"')' /etc/DDNS/.config
                fi
                break
            elif [[ "$enable_ipv6" =~ ^[Nn]$ ]]; then
                ipv6_set="false"
                # 更新 .config 文件中的 ipv6_set 为 false
                sed -i 's/^#\?ipv6_set=".*"/ipv6_set="false"/g' /etc/DDNS/.config
                echo -e "${Info}IPv6 解析未开启，跳过 IPv6 域名设置。"
                echo
                break
            else
                echo -e "${Error}无效输入，请输入 'y' 或 'n'。"
            fi
        done
    else
        echo -e "${Info}未检测到IPv6地址，跳过IPv6域名设置。"
        echo
        ipv6_set="false"
        # 更新 .config 文件中的 ipv6_set 为 false
        sed -i 's/^#\?ipv6_set=".*"/ipv6_set="false"/g' /etc/DDNS/.config
    fi
}

# 设置Telegram参数
set_telegram_settings(){
    echo -e "${Info}开始配置Telegram通知设置..."
    echo

    echo -e "${Tip}请输入您的Telegram Bot Token，如果不使用Telegram通知请直接按 Enter 跳过"
    read -rp "Token: " Token
    if [ -n "$Token" ]; then
        TELEGRAM_BOT_TOKEN="$Token"
        echo -e "${Info}你的TOKEN：${RED_ground}$TELEGRAM_BOT_TOKEN${NC}"
        echo

        echo -e "${Tip}请输入您的Telegram Chat ID，如果不使用Telegram通知请直接按 Enter 跳过"
        read -rp "Chat ID: " Chat_ID
        if [ -n "$Chat_ID" ]; then
            TELEGRAM_CHAT_ID="$Chat_ID"
            echo -e "${Info}你的Chat ID：${RED_ground}$TELEGRAM_CHAT_ID${NC}"
            echo

            sed -i 's/^#\?Telegram_Bot_Token=".*"/Telegram_Bot_Token="'"${TELEGRAM_BOT_TOKEN}"'"/g' /etc/DDNS/.config
            sed -i 's/^#\?Telegram_Chat_ID=".*"/Telegram_Chat_ID="'"${TELEGRAM_CHAT_ID}"'"/g' /etc/DDNS/.config
        else
            echo -e "${Info}已跳过设置Telegram Chat ID"
        fi
    else
        echo -e "${Info}已跳过设置Telegram Bot Token和Chat ID"
        echo
        return  # 如果没有输入 Token，则直接返回，跳过设置 Chat ID 的步骤
    fi
}

# 设置飞书通知
set_feishu_settings(){
    echo -e "${Info}开始配置飞书通知设置..."
    echo

    echo -e "${Tip}请输入您的飞书机器人 Webhook 地址，如果不使用飞书通知请直接按 Enter 跳过"
    echo -e "${YELLOW}在飞书群组 -> 设置 -> 群机器人 -> 添加机器人 -> 自定义机器人 中获取 Webhook 地址${NC}"
    read -rp "Webhook: " Webhook
    if [ -n "$Webhook" ]; then
        FEISHU_WEBHOOK="$Webhook"
        echo -e "${Info}你的飞书 Webhook：${RED_ground}${FEISHU_WEBHOOK}${NC}"
        echo

        echo -e "${Tip}请输入您的飞书机器人签名密钥（Secret），如果不启用签名校验请直接按 Enter 跳过"
        echo -e "${YELLOW}在飞书机器人设置 -> 安全设置 -> 签名校验 中获取${NC}"
        read -rp "Secret: " Secret
        if [ -n "$Secret" ]; then
            FEISHU_SECRET="$Secret"
            echo -e "${Info}已启用飞书签名校验"
            echo
            sed -i 's|^#\?Feishu_Secret=".*"|Feishu_Secret="'"${FEISHU_SECRET}"'"|g' /etc/DDNS/.config
        else
            echo -e "${Info}未启用飞书签名校验"
            echo
            sed -i 's|^#\?Feishu_Secret=".*"|Feishu_Secret=""|g' /etc/DDNS/.config
        fi

        sed -i 's|^#\?Feishu_Webhook=".*"|Feishu_Webhook="'"${FEISHU_WEBHOOK}"'"|g' /etc/DDNS/.config
    else
        echo -e "${Info}已跳过设置飞书通知"
        echo
    fi
}

# 运行DDNS服务
run_ddns() {
    if grep -qiE "alpine" /etc/os-release; then
        # 在 Alpine Linux 上使用 cron
        echo -e "${Info}设置 ddns 脚本每两分钟运行一次..."

        # 检查 cron 任务是否已存在，防止重复添加
        if ! crontab -l | grep -q "/bin/bash /etc/DDNS/DDNS >/dev/null 2>&1"; then
            # 设置 cron 任务
            (crontab -l; echo "*/2 * * * * /bin/bash /etc/DDNS/DDNS >/dev/null 2>&1") | crontab -
            echo -e "${Info}ddns 脚本已设置为每两分钟运行一次！"
        else
            echo -e "${Tip}ddns 脚本的 cron 任务已存在，无需再次创建！"
        fi
    else
        # 在 Debian/Ubuntu 上使用 systemd
        service='[Unit]
Description=ddns
After=network.target

[Service]
Type=simple
WorkingDirectory=/etc/DDNS
ExecStart=bash DDNS

[Install]
WantedBy=multi-user.target'

        timer='[Unit]
Description=ddns timer

[Timer]
OnUnitActiveSec=60s
Unit=ddns.service

[Install]
WantedBy=multi-user.target'

        if [ ! -f "/etc/systemd/system/ddns.service" ] || [ ! -f "/etc/systemd/system/ddns.timer" ]; then
            echo -e "${Info}创建 ddns 定时任务..."
            echo "$service" >/etc/systemd/system/ddns.service
            echo "$timer" >/etc/systemd/system/ddns.timer
            echo -e "${Info}ddns 定时任务已创建，每1分钟执行一次！"
            systemctl enable --now ddns.service >/dev/null 2>&1
            systemctl enable --now ddns.timer >/dev/null 2>&1
        else
            echo -e "${Tip}服务和定时器单元文件已存在，无需再次创建！"
        fi
    fi
}

# 更改 DDNS 服务的运行时间（单位：分钟）
set_ddns_run_interval() {
    read -rp "请输入新的 DDNS 运行间隔（分钟）： " interval

    # 输入验证
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        echo -e "${Error}无效输入！请输入一个正整数。"
        return 1
    fi

    if grep -qiE "alpine" /etc/os-release; then
        # 在 Alpine Linux 上更新 cron 任务
        echo -e "${Info}正在更新 DDNS 脚本的 cron 任务... "

        # 计算 cron 表达式
        local cron_time="*/$interval * * * * /bin/bash /etc/DDNS/DDNS >/dev/null 2>&1"

        # 检查 cron 任务是否已存在，防止重复添加
        if crontab -l | grep -q "/etc/DDNS/DDNS"; then
            # 删除旧的 cron 任务
            (crontab -l | grep -v "/etc/DDNS/DDNS") | crontab -
        fi
        # 添加新的 cron 任务
        (crontab -l; echo "$cron_time") | crontab -
        echo -e "${Info}DDNS 脚本已设置为每 ${interval} 分钟运行一次！"
    else
        # 在 Debian/Ubuntu 上更新 systemd 定时器
        echo -e "${Info}正在更新 DDNS 定时器... "

        # 停止并禁用旧的定时器
        systemctl stop ddns.timer
        systemctl disable ddns.timer

        # 修改定时器文件，将单位设置为分钟
        sed -i "s/OnUnitActiveSec=.*s/OnUnitActiveSec=${interval}m/" /etc/systemd/system/ddns.timer

        # 重新加载 systemd 管理器配置
        systemctl daemon-reload

        # 启动并启用新的定时器
        systemctl enable --now ddns.timer
        echo -e "${Info}DDNS 定时器已设置为每 ${interval} 分钟运行一次！"
    fi
}

restart_ddns() {
    if grep -qiE "alpine" /etc/os-release; then
        echo -e "${Info}重新启动 ddns 脚本..."

        # 获取当前的 cron 任务
        current_cron=$(crontab -l | grep "/bin/bash /etc/DDNS/DDNS" || true)

        # 如果当前的 cron 任务存在，则替换
        if [ -n "$current_cron" ]; then
            # 删除旧的 cron 任务
            crontab -l | grep -v "/bin/bash /etc/DDNS/DDNS" | crontab -

            # 添加新的 cron 任务
            new_cron="${current_cron} >/dev/null 2>&1"
            (crontab -l; echo "$new_cron") | crontab -

            echo -e "${Info}DDNS 已重启！"
        else
            echo -e "${Error}未找到现有的 cron 任务，无法重启 DDNS。"
            read -rp "是否要添加一个新的 DDNS 任务（每 2 分钟）？[y/n] " add_cron
            if [[ "$add_cron" == "y" || "$add_cron" == "Y" ]]; then
                # 添加新的 cron 任务
                new_cron="*/2 * * * * /bin/bash /etc/DDNS/DDNS >/dev/null 2>&1"
                (crontab -l; echo "$new_cron") | crontab -
                echo -e "${Info}已添加新的 DDNS 任务，每 2 分钟运行一次！"
            else
                echo -e "${Info}未添加新的 DDNS 任务。"
                return 1  # 返回失败状态
            fi
        fi
    else
        echo -e "${Info}重启 DDNS 服务... "
        systemctl restart ddns.service >/dev/null 2>&1
        systemctl restart ddns.timer >/dev/null 2>&1
        echo -e "${Info}DDNS 已重启！"
    fi
}

# 停止DDNS服务
stop_ddns(){
    if grep -qiE "alpine" /etc/os-release; then
        echo -e "${Info}停止 ddns 脚本..."
        # 从 cron 中移除 ddns 任务
        crontab -l | grep -v "/bin/bash /etc/DDNS/DDNS >/dev/null 2>&1" | crontab -
        echo -e "${Info}DDNS 已停止！"
    else
        echo -e "${Info}停止 DDNS 服务..."
        systemctl stop ddns.service >/dev/null 2>&1
        systemctl stop ddns.timer >/dev/null 2>&1
        echo -e "${Info}DDNS 已停止！"
    fi
}

# 检查是否安装DDNS
check_ddns_install(){
    if [ ! -f "/etc/DDNS/.config" ]; then
        install_ddns
    fi

    cop_info
    check_ddns_status
    if [[ "$ddns_status" == "running" ]]; then
        echo -e "${Info}DDNS：${GREEN}已安装${NC} 并 ${GREEN}已启动${NC}"
    else
        echo -e "${Tip}DDNS：${GREEN}已安装${NC} 但 ${RED}未启动${NC}"
    fi
    echo
    go_ahead
}

check_curl
check_ddns_install