package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

func appendLog(msg string) {
	f, err := os.OpenFile(logPath(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	f.WriteString(fmt.Sprintf("[%s] %s\n", time.Now().Format("2006-01-02 15:04:05"), msg))
}

func RunUpdate() {
	appendLog("===== DDNS 更新开始 =====")
	cfg, err := LoadConfig()
	if err != nil {
		appendLog("[ERROR] 读取配置失败: " + err.Error())
		return
	}

	provider, err := NewDNSProvider(cfg)
	if err != nil {
		appendLog("[ERROR] " + err.Error())
		return
	}

	newIPv4 := GetPublicIPv4()
	var newIPv6 string
	if cfg.IPv6Set == "true" {
		newIPv6 = GetPublicIPv6()
	}
	appendLog(fmt.Sprintf("[INFO] 当前公网 IPv4: %s", newIPv4))
	if newIPv6 != "" {
		appendLog(fmt.Sprintf("[INFO] 当前公网 IPv6: %s", newIPv6))
	}
	oldIPv4 := cfg.PublicIPv4
	oldIPv6 := cfg.PublicIPv6
	changed := false

	if newIPv4 != "" && len(cfg.Domains) > 0 {
		for _, domain := range cfg.Domains {
			domain = strings.TrimSpace(domain)
			if domain == "" {
				continue
			}
			ok, err := provider.UpdateRecord(domain, "A", newIPv4)
			if err != nil {
				appendLog(fmt.Sprintf("[ERROR] %s: %v", domain, err))
			} else if ok {
				appendLog(fmt.Sprintf("[INFO] %s -> %s 更新成功", domain, newIPv4))
				changed = true
			} else {
				appendLog(fmt.Sprintf("[ERROR] %s -> %s 更新失败", domain, newIPv4))
			}
		}
		if newIPv4 != oldIPv4 {
			changed = true
			cfg.PublicIPv4 = newIPv4
		}
	}

	if cfg.IPv6Set == "true" && newIPv6 != "" && len(cfg.Domainsv6) > 0 {
		for _, domain := range cfg.Domainsv6 {
			domain = strings.TrimSpace(domain)
			if domain == "" {
				continue
			}
			ok, err := provider.UpdateRecord(domain, "AAAA", newIPv6)
			if err != nil {
				appendLog(fmt.Sprintf("[ERROR] %s: %v", domain, err))
			} else if ok {
				appendLog(fmt.Sprintf("[INFO] %s -> %s 更新成功", domain, newIPv6))
				changed = true
			} else {
				appendLog(fmt.Sprintf("[ERROR] %s -> %s 更新失败", domain, newIPv6))
			}
		}
		if newIPv6 != oldIPv6 {
			changed = true
			cfg.PublicIPv6 = newIPv6
		}
	}

	if changed {
		msg := buildNotifyMessage(cfg, oldIPv4, newIPv4, oldIPv6, newIPv6)
		if cfg.TelegramBotToken != "" && cfg.TelegramChatID != "" {
			sendTelegram(cfg.TelegramBotToken, cfg.TelegramChatID, msg)
			appendLog("[INFO] Telegram 通知已发送")
		}
		if cfg.FeishuWebhook != "" {
			sendFeishu(cfg.FeishuWebhook, cfg.FeishuSecret, msg)
			appendLog("[INFO] 飞书通知已发送")
		}
	}
	data, _ := json.MarshalIndent(cfg, "", "  ")
	os.WriteFile(configPath(), data, 0600)
	appendLog("===== DDNS 更新完成 =====")
}
