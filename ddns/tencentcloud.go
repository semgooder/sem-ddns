package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const tcEndpoint = "dnspod.tencentcloudapi.com"
const tcService = "dnspod"
const tcVersion = "2021-03-23"

type tencentcloudProvider struct {
	SecretId  string
	SecretKey string
}

func (p *tencentcloudProvider) UpdateRecord(fullDomain, recordType, value string) (bool, error) {
	root, sub := splitDomain(fullDomain)

	// 1. 获取域名列表
	domainID, err := p.describeDomainList(root)
	if err != nil {
		return false, fmt.Errorf("获取域名信息失败: %v", err)
	}

	// 2. 获取记录 ID
	recordID, err := p.describeRecordList(domainID, sub, recordType)
	if err != nil {
		return false, fmt.Errorf("获取记录失败: %v", err)
	}

	// 3. 修改记录
	return p.modifyRecord(domainID, recordID, sub, recordType, value)
}

// tcRequest 调用腾讯云 API v3（TC3-HMAC-SHA256）
func (p *tencentcloudProvider) tcRequest(action string, payload interface{}) ([]byte, error) {
	body, _ := json.Marshal(payload)
	timestamp := time.Now().Unix()
	date := time.Now().UTC().Format("2006-01-02")

	// 1. 拼接 CanonicalRequest
	canonicalURI := "/"
	canonicalQS := ""
	canonicalHeaders := fmt.Sprintf("content-type:%s\nhost:%s\nx-tc-action:%s\n",
		"application/json", tcEndpoint, strings.ToLower(action))
	signedHeaders := "content-type;host;x-tc-action"
	hashedPayload := sha256Hex(string(body))

	canonicalRequest := fmt.Sprintf("POST\n%s\n%s\n%s\n%s\n%s",
		canonicalURI, canonicalQS, canonicalHeaders, signedHeaders, hashedPayload)

	// 2. 拼接待签字符串
	algorithm := "TC3-HMAC-SHA256"
	credentialScope := fmt.Sprintf("%s/%s/tc3_request", date, tcService)
	hashedCR := sha256Hex(canonicalRequest)
	stringToSign := fmt.Sprintf("%s\n%d\n%s\n%s", algorithm, timestamp, credentialScope, hashedCR)

	// 3. 计算签名
	signKey := hmacSHA256([]byte("TC3"+p.SecretKey), date)
	signKey = hmacSHA256(signKey, tcService)
	signKey = hmacSHA256(signKey, "tc3_request")
	signature := hex.EncodeToString(hmacSHA256(signKey, stringToSign))

	// 4. 拼接 Authorization
	authorization := fmt.Sprintf("%s Credential=%s/%s, SignedHeaders=%s, Signature=%s",
		algorithm, p.SecretId, credentialScope, signedHeaders, signature)

	// 5. 发送请求
	req, _ := http.NewRequest("POST", "https://"+tcEndpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Host", tcEndpoint)
	req.Header.Set("X-TC-Action", action)
	req.Header.Set("X-TC-Version", tcVersion)
	req.Header.Set("X-TC-Timestamp", fmt.Sprintf("%d", timestamp))
	req.Header.Set("Authorization", authorization)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

func (p *tencentcloudProvider) describeDomainList(domain string) (string, error) {
	body, err := p.tcRequest("DescribeDomainList", map[string]interface{}{
		"Keyword": domain,
	})
	if err != nil {
		return "", err
	}

	var result struct {
		Response struct {
			DomainList []struct {
				DomainId   uint64 `json:"DomainId"`
				Name string `json:"Name"`
			} `json:"DomainList"`
			Error *struct {
				Message string `json:"Message"`
			} `json:"Error"`
		} `json:"Response"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", err
	}
	if result.Response.Error != nil {
		return "", fmt.Errorf("API 错误: %s", result.Response.Error.Message)
	}

	for _, d := range result.Response.DomainList {
		if d.Name == domain {
			return fmt.Sprintf("%d", d.DomainId), nil
		}
	}
	return "", fmt.Errorf("未找到域名 %s", domain)
}

func (p *tencentcloudProvider) describeRecordList(domainID, subDomain, recordType string) (string, error) {
	body, err := p.tcRequest("DescribeRecordList", map[string]interface{}{
		"DomainId":  domainID,
		"Subdomain": subDomain,
	})
	if err != nil {
		return "", err
	}

	type recordItem struct {
		RecordId uint64 `json:"RecordId"`
		Name     string `json:"Name"`
		Type     string `json:"Type"`
	}

	// 有些情况下可能是直接返回 RecordList，也可能包在 Response 里
	var result struct {
		Response struct {
			RecordList []recordItem `json:"RecordList"`
			Error      *struct {
				Message string `json:"Message"`
			} `json:"Error"`
		} `json:"Response"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", err
	}
	if result.Response.Error != nil {
		return "", fmt.Errorf("API 错误: %s", result.Response.Error.Message)
	}

	for _, r := range result.Response.RecordList {
		if r.Type == recordType {
			return fmt.Sprintf("%d", r.RecordId), nil
		}
	}
	return "", fmt.Errorf("未找到 %s 记录", recordType)
}

func (p *tencentcloudProvider) modifyRecord(domainID, recordID, subDomain, recordType, value string) (bool, error) {
	payload := map[string]interface{}{
		"DomainId":  domainID,
		"RecordId":  recordID,
		"SubDomain": subDomain,
		"RecordType": recordType,
		"RecordLine": "默认",
		"Value":     value,
	}
	body, err := p.tcRequest("ModifyRecord", payload)
	if err != nil {
		return false, err
	}

	var result struct {
		Response struct {
			Error *struct {
				Message string `json:"Message"`
			} `json:"Error"`
		} `json:"Response"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return false, err
	}
	if result.Response.Error != nil {
		return false, fmt.Errorf("修改失败: %s", result.Response.Error.Message)
	}
	return true, nil
}

func sha256Hex(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

func hmacSHA256(key []byte, data string) []byte {
	h := hmac.New(sha256.New, key)
	h.Write([]byte(data))
	return h.Sum(nil)
}
