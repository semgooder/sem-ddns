package main

import (
	"io"
	"net/http"
	"strings"
	"time"
)

var ipv4URLs = []string{
	"https://api.ipify.org",
	"https://ip.sb",
	"https://ipv4.icanhazip.com",
}

var ipv6URLs = []string{
	"https://api6.ipify.org",
	"https://ip.sb",
}

func httpGet(url string) (string, error) {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

func GetPublicIPv4() string {
	for _, url := range ipv4URLs {
		ip, err := httpGet(url)
		if err == nil && isValidIPv4(ip) {
			return ip
		}
	}
	return ""
}

func GetPublicIPv6() string {
	for _, url := range ipv6URLs {
		ip, err := httpGet(url)
		if err == nil && isValidIPv6(ip) {
			return ip
		}
	}
	return ""
}

func isValidIPv4(ip string) bool {
	parts := strings.Split(ip, ".")
	if len(parts) != 4 {
		return false
	}
	for _, p := range parts {
		if len(p) == 0 || len(p) > 3 {
			return false
		}
		for _, c := range p {
			if c < '0' || c > '9' {
				return false
			}
		}
	}
	return true
}

func isValidIPv6(ip string) bool {
	return strings.Contains(ip, ":")
}
