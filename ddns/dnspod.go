package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const dnspodAPI = "https://dnsapi.cn"

type dnspodProvider struct {
	LoginID    string
	LoginToken string
}

type dnspodRecord struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Type   string `json:"type"`
	Value  string `json:"value"`
	LineID string `json:"line_id"`
}

type dnspodResponse struct {
	Status struct {
		Code string `json:"code"`
	} `json:"status"`
	Records []dnspodRecord `json:"records"`
	Record  dnspodRecord   `json:"record"`
}

func (p *dnspodProvider) UpdateRecord(fullDomain, recordType, value string) (bool, error) {
	root, sub := splitDomain(fullDomain)

	// 1. 获取域名列表，找到 root domain 的 ID
	domainID, err := p.getDomainID(root)
	if err != nil {
		return false, fmt.Errorf("获取域名 %s 信息失败: %v", root, err)
	}

	// 2. 查询记录列表，找到匹配的记录 ID
	recordID, err := p.getRecordID(domainID, sub, recordType)
	if err != nil {
		return false, fmt.Errorf("获取记录失败: %v", err)
	}

	// 3. 修改记录
	return p.modifyRecord(domainID, recordID, sub, recordType, value)
}

func (p *dnspodProvider) post(action string, params map[string]string) ([]byte, error) {
	data := url.Values{}
	data.Set("login_token", p.LoginID+","+p.LoginToken)
	data.Set("format", "json")
	for k, v := range params {
		data.Set(k, v)
	}

	req, err := http.NewRequest("POST", dnspodAPI+action, strings.NewReader(data.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("User-Agent", "sem-ddns/1.0")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

func (p *dnspodProvider) getDomainID(domain string) (string, error) {
	body, err := p.post("/Domain.List", map[string]string{})
	if err != nil {
		return "", err
	}

	var result struct {
		Status struct {
			Code string `json:"code"`
		} `json:"status"`
		Domains []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"domains"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", err
	}
	if result.Status.Code != "1" {
		return "", fmt.Errorf("API 返回错误码: %s", result.Status.Code)
	}

	for _, d := range result.Domains {
		if d.Name == domain {
			return d.ID, nil
		}
	}
	return "", fmt.Errorf("未找到域名 %s", domain)
}

func (p *dnspodProvider) getRecordID(domainID, subDomain, recordType string) (string, error) {
	params := map[string]string{
		"domain_id":  domainID,
		"sub_domain": subDomain,
	}
	body, err := p.post("/Record.List", params)
	if err != nil {
		return "", err
	}

	var result struct {
		Status struct {
			Code string `json:"code"`
		} `json:"status"`
		Records []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
			Type string `json:"type"`
		} `json:"records"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", err
	}
	if result.Status.Code != "1" {
		return "", fmt.Errorf("API 返回错误码: %s", result.Status.Code)
	}

	for _, r := range result.Records {
		if r.Type == recordType {
			return r.ID, nil
		}
	}
	return "", fmt.Errorf("未找到 %s 记录", recordType)
}

func (p *dnspodProvider) modifyRecord(domainID, recordID, subDomain, recordType, value string) (bool, error) {
	params := map[string]string{
		"domain_id":   domainID,
		"record_id":   recordID,
		"sub_domain":  subDomain,
		"record_type": recordType,
		"record_line": "默认",
		"value":       value,
	}
	body, err := p.post("/Record.Modify", params)
	if err != nil {
		return false, err
	}

	var result struct {
		Status struct {
			Code string `json:"code"`
		} `json:"status"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return false, err
	}
	if result.Status.Code != "1" {
		return false, fmt.Errorf("修改失败, API 返回: %s", result.Status.Code)
	}
	return true, nil
}

// splitDomain 将完整域名拆分为 root 和 sub
// example.com -> root=example.com, sub=@
// www.example.com -> root=example.com, sub=www
// a.b.example.com -> root=example.com, sub=a.b
func splitDomain(full string) (root, sub string) {
	parts := strings.Split(full, ".")
	if len(parts) < 2 {
		return full, "@"
	}
	// 取最后两部分作为 root
	root = parts[len(parts)-2] + "." + parts[len(parts)-1]
	if full == root {
		return root, "@"
	}
	sub = full[:len(full)-len(root)-1]
	return root, sub
}
