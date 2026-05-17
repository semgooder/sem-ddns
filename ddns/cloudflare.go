package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"
)

const cfAPI = "https://api.cloudflare.com/client/v4"

type cloudflareProvider struct {
	APIToken string
}

type cfResponse struct {
	Success bool           `json:"success"`
	Result  []cfZoneResult `json:"result"`
}

type cfZoneResult struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type cfDNSListResponse struct {
	Success bool          `json:"success"`
	Result  []cfDNSResult `json:"result"`
}

type cfDNSResult struct {
	ID string `json:"id"`
}

type cfUpdateResponse struct {
	Success bool `json:"success"`
}

func (p *cloudflareProvider) UpdateRecord(domain, recordType, value string) (bool, error) {
	zoneID := p.getZoneID(domain)
	if zoneID == "" {
		return false, fmt.Errorf("未找到 %s 对应的 Zone", domain)
	}

	recordID := p.getDNSRecordID(zoneID, recordType, domain)
	if recordID == "" {
		return false, fmt.Errorf("未找到 %s 的 %s 记录", domain, recordType)
	}

	return p.updateDNSRecord(zoneID, recordID, recordType, domain, value), nil
}

func (p *cloudflareProvider) getZoneID(domain string) string {
	req, _ := http.NewRequest("GET", cfAPI+"/zones", nil)
	req.Header.Set("Authorization", "Bearer "+p.APIToken)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var result cfResponse
	if err := json.Unmarshal(body, &result); err != nil || !result.Success {
		return ""
	}

	sort.Slice(result.Result, func(i, j int) bool {
		return len(result.Result[i].Name) > len(result.Result[j].Name)
	})

	for _, zone := range result.Result {
		if domain == zone.Name || strings.HasSuffix(domain, "."+zone.Name) {
			return zone.ID
		}
	}
	return ""
}

func (p *cloudflareProvider) getDNSRecordID(zoneID, recordType, name string) string {
	url := fmt.Sprintf("%s/zones/%s/dns_records?type=%s&name=%s", cfAPI, zoneID, recordType, name)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+p.APIToken)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var result cfDNSListResponse
	if err := json.Unmarshal(body, &result); err != nil || !result.Success || len(result.Result) == 0 {
		return ""
	}
	return result.Result[0].ID
}

func (p *cloudflareProvider) updateDNSRecord(zoneID, recordID, recordType, name, content string) bool {
	payload := map[string]string{
		"type":    recordType,
		"name":    name,
		"content": content,
	}
	data, _ := json.Marshal(payload)

	url := fmt.Sprintf("%s/zones/%s/dns_records/%s", cfAPI, zoneID, recordID)
	req, _ := http.NewRequest("PUT", url, bytes.NewReader(data))
	req.Header.Set("Authorization", "Bearer "+p.APIToken)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var result cfUpdateResponse
	json.Unmarshal(body, &result)
	return result.Success
}
