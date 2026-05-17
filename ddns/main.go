package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "run":
			RunUpdate()
			return
		case "install":
			InstallServiceC()
			return
		case "uninstall":
			UninstallServiceC()
			return
		case "config":
			runWizard()
			return
		}
	}

	cfg, _ := LoadConfig()
	if cfg == nil {
		cfg = &Config{}
		SaveConfig(cfg)
	}

	showMenu()
}

func selectProvider(r *bufio.Reader) string {
	fmt.Println("\n选择 DNS 服务商：")
	fmt.Println("  1) Cloudflare")
	fmt.Println("  2) DNSPod（独立版，使用 ID + Token）")
	fmt.Println("  3) 腾讯云 DNSPod（API 3.0，使用 SecretId + SecretKey）")
	fmt.Print("请选择 [1/2/3] (默认 1): ")
	opt, _ := r.ReadString('\n')
	opt = strings.TrimSpace(opt)
	switch opt {
	case "2":
		return "dnspod"
	case "3":
		return "tencentcloud"
	default:
		return "cloudflare"
	}
}

func runWizard() {
	r := bufio.NewReader(os.Stdin)
	fmt.Println("========== DDNS 配置向导 ==========")

	var cfg Config
	cfg.Provider = selectProvider(r)

	switch cfg.Provider {
	case "dnspod":
		fmt.Print("请输入 DNSPod ID: ")
		id, _ := r.ReadString('\n')
		cfg.DNSPodID = strings.TrimSpace(id)
		fmt.Print("请输入 DNSPod Token: ")
		tok, _ := r.ReadString('\n')
		cfg.DNSPodToken = strings.TrimSpace(tok)
		if cfg.DNSPodID == "" || cfg.DNSPodToken == "" {
			fmt.Println("DNSPod ID 和 Token 不能为空")
			return
		}

	case "tencentcloud":
		fmt.Print("请输入腾讯云 SecretId: ")
		id, _ := r.ReadString('\n')
		cfg.SecretId = strings.TrimSpace(id)
		fmt.Print("请输入腾讯云 SecretKey: ")
		key, _ := r.ReadString('\n')
		cfg.SecretKey = strings.TrimSpace(key)
		if cfg.SecretId == "" || cfg.SecretKey == "" {
			fmt.Println("SecretId 和 SecretKey 不能为空")
			return
		}

	default:
		fmt.Print("请输入 Cloudflare API Token: ")
		token, _ := r.ReadString('\n')
		cfg.APIToken = strings.TrimSpace(token)
		if cfg.APIToken == "" {
			fmt.Println("API Token 不能为空")
			return
		}
	}

	fmt.Println("\n检测公网 IP...")
	ipv4 := GetPublicIPv4()
	if ipv4 != "" {
		fmt.Printf("检测到公网 IPv4: %s\n", ipv4)
		fmt.Print("请输入要解析的 IPv4 域名（多个用逗号分隔，直接回车跳过）: ")
		input, _ := r.ReadString('\n')
		input = strings.TrimSpace(input)
		if input != "" {
			for _, d := range strings.Split(input, ",") {
				d = strings.TrimSpace(d)
				if d != "" {
					cfg.Domains = append(cfg.Domains, d)
				}
			}
			fmt.Printf("IPv4 域名: %s\n", strings.Join(cfg.Domains, ", "))
		}
	} else {
		fmt.Println("未检测到 IPv4 地址，跳过")
	}

	ipv6 := GetPublicIPv6()
	if ipv6 != "" {
		fmt.Printf("检测到公网 IPv6: %s\n", ipv6)
		fmt.Print("是否开启 IPv6 解析？(y/n): ")
		yn, _ := r.ReadString('\n')
		if strings.TrimSpace(strings.ToLower(yn)) == "y" {
			cfg.IPv6Set = "true"
			fmt.Print("请输入要解析的 IPv6 域名（多个用逗号分隔，直接回车跳过）: ")
			input, _ := r.ReadString('\n')
			input = strings.TrimSpace(input)
			if input != "" {
				for _, d := range strings.Split(input, ",") {
					d = strings.TrimSpace(d)
					if d != "" {
						cfg.Domainsv6 = append(cfg.Domainsv6, d)
					}
				}
				fmt.Printf("IPv6 域名: %s\n", strings.Join(cfg.Domainsv6, ", "))
			}
		}
	} else {
		fmt.Println("未检测到 IPv6 地址，跳过")
	}

	fmt.Print("\n是否配置 Telegram 通知？(y/n): ")
	yn, _ := r.ReadString('\n')
	if strings.TrimSpace(strings.ToLower(yn)) == "y" {
		fmt.Print("Telegram Bot Token: ")
		t, _ := r.ReadString('\n')
		cfg.TelegramBotToken = strings.TrimSpace(t)
		fmt.Print("Telegram Chat ID: ")
		c, _ := r.ReadString('\n')
		cfg.TelegramChatID = strings.TrimSpace(c)
	}

	fmt.Print("是否配置飞书通知？(y/n): ")
	yn, _ = r.ReadString('\n')
	if strings.TrimSpace(strings.ToLower(yn)) == "y" {
		fmt.Print("飞书 Webhook 地址: ")
		w, _ := r.ReadString('\n')
		cfg.FeishuWebhook = strings.TrimSpace(w)
		fmt.Print("飞书签名密钥 Secret（如未启用直接回车）: ")
		s, _ := r.ReadString('\n')
		cfg.FeishuSecret = strings.TrimSpace(s)
	}

	if err := SaveConfig(&cfg); err != nil {
		fmt.Printf("保存配置失败: %v\n", err)
		return
	}
	fmt.Println("\n配置已保存！")

	fmt.Print("是否安装 Windows 服务（开机自启）？(y/n): ")
	yn, _ = r.ReadString('\n')
	if strings.TrimSpace(strings.ToLower(yn)) == "y" {
		InstallServiceC()
	}

	fmt.Println("\n完成！运行程序可呼出菜单")
	pause()
}

func showMenu() {
	for {
		clearScreen()
		fmt.Println("######################################")
		fmt.Println("#   Cloudflare DDNS (Go 版)          #")
		fmt.Println("######################################")
		fmt.Println()

		cfg, _ := LoadConfig()
		fmt.Printf("DNS 服务商: %s\n", providerDisplayName(cfg))
		fmt.Printf("配置文件: %s\n", configPath())
		fmt.Printf("日志文件: %s\n", logPath())
		fmt.Println()

		fmt.Println("请选择一个选项：")
		fmt.Println("  0：退出")
		fmt.Println("  1：立即执行 DDNS 更新")
		fmt.Println("  2：切换 DNS 服务商")
		fmt.Println("  3：配置 DNS 凭证")
		fmt.Println("  4：配置要解析的域名")
		fmt.Println("  5：配置 Telegram 通知")
		fmt.Println("  6：配置飞书通知")
		fmt.Println("  7：安装 Windows 服务（开机自启）")
		fmt.Println("  8：卸载 Windows 服务")

		fmt.Print("\n选项: ")
		r := bufio.NewReader(os.Stdin)
		opt, _ := r.ReadString('\n')
		opt = strings.TrimSpace(opt)

		switch opt {
		case "0":
			return
		case "1":
			RunUpdate()
			pause()
		case "2":
			cfg, _ := LoadConfig()
			if cfg == nil {
				cfg = &Config{}
			}
			cfg.Provider = selectProvider(r)
			SaveConfig(cfg)
			fmt.Println("已切换")
			pause()
		case "3":
			cfg, _ := LoadConfig()
			if cfg == nil {
				cfg = &Config{}
			}
			switch cfg.Provider {
			case "dnspod":
				fmt.Print("DNSPod ID: ")
				id, _ := r.ReadString('\n')
				cfg.DNSPodID = strings.TrimSpace(id)
				fmt.Print("DNSPod Token: ")
				tok, _ := r.ReadString('\n')
				cfg.DNSPodToken = strings.TrimSpace(tok)
			case "tencentcloud":
				fmt.Print("SecretId: ")
				id, _ := r.ReadString('\n')
				cfg.SecretId = strings.TrimSpace(id)
				fmt.Print("SecretKey: ")
				key, _ := r.ReadString('\n')
				cfg.SecretKey = strings.TrimSpace(key)
			default:
				fmt.Print("Cloudflare API Token: ")
				t, _ := r.ReadString('\n')
				cfg.APIToken = strings.TrimSpace(t)
			}
			SaveConfig(cfg)
			fmt.Println("已保存")
			pause()
		case "4":
			cfg, _ := LoadConfig()
			if cfg == nil {
				cfg = &Config{}
			}
			ipv4 := GetPublicIPv4()
			if ipv4 != "" {
				fmt.Printf("公网 IPv4: %s\n", ipv4)
				fmt.Print("IPv4 域名（多个用逗号分隔，直接回车跳过）: ")
				input, _ := r.ReadString('\n')
				input = strings.TrimSpace(input)
				if input != "" {
					var domains []string
					for _, d := range strings.Split(input, ",") {
						d = strings.TrimSpace(d)
						if d != "" {
							domains = append(domains, d)
						}
					}
					cfg.Domains = domains
				}
			}
			ipv6 := GetPublicIPv6()
			if ipv6 != "" {
				fmt.Printf("公网 IPv6: %s\n", ipv6)
				fmt.Print("开启 IPv6? (y/n): ")
				yn, _ := r.ReadString('\n')
				if strings.TrimSpace(strings.ToLower(yn)) == "y" {
					cfg.IPv6Set = "true"
					fmt.Print("IPv6 域名（多个用逗号分隔，直接回车跳过）: ")
					input, _ := r.ReadString('\n')
					input = strings.TrimSpace(input)
					if input != "" {
						var domains []string
						for _, d := range strings.Split(input, ",") {
							d = strings.TrimSpace(d)
							if d != "" {
								domains = append(domains, d)
							}
						}
						cfg.Domainsv6 = domains
					}
				} else {
					cfg.IPv6Set = "false"
				}
			}
			SaveConfig(cfg)
			fmt.Println("已保存")
			pause()
		case "5":
			cfg, _ := LoadConfig()
			if cfg == nil {
				cfg = &Config{}
			}
			fmt.Print("Telegram Bot Token（直接回车跳过）: ")
			t, _ := r.ReadString('\n')
			t = strings.TrimSpace(t)
			if t != "" {
				cfg.TelegramBotToken = t
				fmt.Print("Telegram Chat ID: ")
				c, _ := r.ReadString('\n')
				cfg.TelegramChatID = strings.TrimSpace(c)
				SaveConfig(cfg)
				fmt.Println("已保存")
			}
			pause()
		case "6":
			cfg, _ := LoadConfig()
			if cfg == nil {
				cfg = &Config{}
			}
			fmt.Print("飞书 Webhook 地址（直接回车跳过）: ")
			w, _ := r.ReadString('\n')
			w = strings.TrimSpace(w)
			if w != "" {
				cfg.FeishuWebhook = w
				fmt.Print("签名 Secret（如未启用直接回车）: ")
				s, _ := r.ReadString('\n')
				cfg.FeishuSecret = strings.TrimSpace(s)
				SaveConfig(cfg)
				fmt.Println("已保存")
			}
			pause()
		case "7":
			InstallServiceC()
			pause()
		case "8":
			UninstallServiceC()
			pause()
		}
	}
}

func providerDisplayName(cfg *Config) string {
	if cfg == nil {
		return "未配置"
	}
	switch cfg.Provider {
	case "dnspod":
		return "DNSPod（独立版）"
	case "tencentcloud":
		return "腾讯云 DNSPod（API 3.0）"
	case "cloudflare":
		return "Cloudflare"
	default:
		return "未配置"
	}
}

func pause() {
	fmt.Print("\n按回车键继续...")
	bufio.NewReader(os.Stdin).ReadString('\n')
}

func clearScreen() {
	fmt.Print("\033[H\033[2J")
}

func InstallServiceC() {
	InstallService()
}

func UninstallServiceC() {
	UninstallService()
}
