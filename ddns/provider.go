package main

import "fmt"

type DNSProvider interface {
	UpdateRecord(domain, recordType, value string) (bool, error)
}

func NewDNSProvider(cfg *Config) (DNSProvider, error) {
	switch cfg.Provider {
	case "dnspod":
		if cfg.DNSPodID == "" || cfg.DNSPodToken == "" {
			return nil, fmt.Errorf("DNSPod ID 和 Token 未配置")
		}
		return &dnspodProvider{LoginID: cfg.DNSPodID, LoginToken: cfg.DNSPodToken}, nil

	case "tencentcloud":
		if cfg.SecretId == "" || cfg.SecretKey == "" {
			return nil, fmt.Errorf("腾讯云 SecretId 和 SecretKey 未配置")
		}
		return &tencentcloudProvider{SecretId: cfg.SecretId, SecretKey: cfg.SecretKey}, nil

	default:
		if cfg.APIToken == "" {
			return nil, fmt.Errorf("Cloudflare API Token 未配置")
		}
		return &cloudflareProvider{APIToken: cfg.APIToken}, nil
	}
}
