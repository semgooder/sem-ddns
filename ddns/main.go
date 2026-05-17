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
	if cfg == nil || cfg.APIToken == "" {
		runWizard()
		return
	}

	showMenu()
}

func runWizard() {
	r := bufio.NewReader(os.Stdin)
	fmt.Println("========== Cloudflare DDNS 配置向导 ==========")

	var cfg Config

	fmt.Print("请输入您的 Cloudflare API Token: ")
	token, _ := r.ReadString('\n')
	cfg.APIToken = strings.TrimSpace(token)
	if cfg.APIToken == "" {
		fmt.Println("API Token 不能为空")
		return
	}

	fmt.Println("检测公网 IP...")
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

	fmt.Print("是否配置 Telegram 通知？(y/n): ")
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
	fmt.Println("配置已保存！")

	fmt.Print("是否安装 Windows 服务（开机自启）？(y/n): ")
	yn, _ = r.ReadString('\n')
	if strings.TrimSpace(strings.ToLower(yn)) == "y" {
		InstallServiceC()
	}

	fmt.Println("完成！运行程序可呼出菜单")
	pause()
}

func showMenu() {
	for {
		clearScreen()
		fmt.Println("######################################")
		fmt.Println("#   Cloudflare DDNS (Go 版)          #")
		fmt.Println("######################################")
		fmt.Println()

		exe, _ := os.Executable()
		fmt.Printf("当前程序: %s\n", exe)
		fmt.Printf("配置文件: %s\n", configPath())
		fmt.Printf("日志文件: %s\n", logPath())
		fmt.Println()

		fmt.Println("请选择一个选项：")
		fmt.Println("  0：退出")
		fmt.Println("  1：立即执行 DDNS 更新")
		fmt.Println("  2：配置 Cloudflare API Token")
		fmt.Println("  3：配置要解析的域名")
		fmt.Println("  4：配置 Telegram 通知")
		fmt.Println("  5：配置飞书通知")
		fmt.Println("  6：安装 Windows 服务（开机自启）")
		fmt.Println("  7：卸载 Windows 服务")

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
			fmt.Print("请输入 Cloudflare API Token: ")
			t, _ := r.ReadString('\n')
			cfg.APIToken = strings.TrimSpace(t)
			if cfg.APIToken != "" {
				SaveConfig(cfg)
				fmt.Println("已保存")
			}
			pause()
		case "3":
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
		case "4":
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
		case "5":
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
		case "6":
			InstallServiceC()
			pause()
		case "7":
			UninstallServiceC()
			pause()
		}
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
