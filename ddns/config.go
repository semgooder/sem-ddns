package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type Config struct {
	Domains         []string `json:"Domains"`
	IPv6Set         string   `json:"ipv6_set"`
	Domainsv6       []string `json:"Domainsv6"`
	APIToken        string   `json:"API_Token"`
	TelegramBotToken string  `json:"Telegram_Bot_Token"`
	TelegramChatID  string   `json:"Telegram_Chat_ID"`
	FeishuWebhook   string   `json:"Feishu_Webhook"`
	FeishuSecret    string   `json:"Feishu_Secret"`
	PublicIPv4      string   `json:"Public_IPv4"`
	PublicIPv6      string   `json:"Public_IPv6"`
}

func configDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".ddns")
}

func configPath() string {
	return filepath.Join(configDir(), "config.json")
}

func logPath() string {
	return filepath.Join(configDir(), "ddns.log")
}

func LoadConfig() (*Config, error) {
	data, err := os.ReadFile(configPath())
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func SaveConfig(cfg *Config) error {
	dir := configDir()
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(configPath(), data, 0600)
}
