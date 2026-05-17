package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type tgPayload struct {
	ChatID string `json:"chat_id"`
	Text   string `json:"text"`
}

func sendTelegram(botToken, chatID, text string) {
	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", botToken)
	payload := tgPayload{ChatID: chatID, Text: text}
	data, _ := json.Marshal(payload)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, "application/json", bytes.NewReader(data))
	if err == nil {
		resp.Body.Close()
	}
}

type feishuContent struct {
	Text string `json:"text"`
}

type feishuPayload struct {
	MsgType   string         `json:"msg_type"`
	Content   feishuContent  `json:"content"`
	Timestamp string         `json:"timestamp,omitempty"`
	Sign      string         `json:"sign,omitempty"`
}

func sendFeishu(webhook, secret, text string) {
	payload := feishuPayload{
		MsgType: "text",
		Content: feishuContent{Text: text},
	}

	if secret != "" {
		timestamp := strconv.FormatInt(time.Now().Unix(), 10)
		signStr := timestamp + "\n" + secret
		mac := hmac.New(sha256.New, []byte(secret))
		mac.Write([]byte(signStr))
		sign := base64.StdEncoding.EncodeToString(mac.Sum(nil))
		payload.Timestamp = timestamp
		payload.Sign = sign
	}

	data, _ := json.Marshal(payload)
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(webhook, "application/json", bytes.NewReader(data))
	if err == nil {
		resp.Body.Close()
	}
}

func buildNotifyMessage(cfg *Config, oldIPv4, newIPv4, oldIPv6, newIPv6 string) string {
	parts := []string{}
	if len(cfg.Domains) > 0 {
		parts = append(parts, strings.Join(cfg.Domains, " "))
	}
	if newIPv4 != "" && newIPv4 != oldIPv4 {
		parts = append(parts, fmt.Sprintf("IPv4更新 %s -> %s", oldIPv4, newIPv4))
	}
	if cfg.IPv6Set == "true" && newIPv6 != "" && newIPv6 != oldIPv6 {
		d1 := strings.Join(cfg.Domains, "")
		d2 := strings.Join(cfg.Domainsv6, "")
		if len(cfg.Domainsv6) > 0 && d1 != d2 {
			parts = append(parts, strings.Join(cfg.Domainsv6, " "))
		}
		parts = append(parts, fmt.Sprintf("IPv6更新 %s -> %s", oldIPv6, newIPv6))
	}
	return strings.Join(parts, " 。")
}
