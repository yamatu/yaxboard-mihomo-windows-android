package main

import (
	"fmt"
	"strings"

	"github.com/metacubex/mihomo/common/convert"
	"github.com/metacubex/mihomo/config"
)

func parseRawConfigWithSubscriptionCompat(buf []byte) (*config.RawConfig, error) {
	rawCfg, err := config.UnmarshalRawConfig(buf)
	if err == nil {
		return rawCfg, nil
	}

	if !looksLikeV2RaySubscription(buf) {
		return nil, err
	}

	compatCfg, compatErr := convertV2RaySubscriptionToRawConfig(buf)
	if compatErr != nil {
		return nil, err
	}

	return compatCfg, nil
}

func looksLikeV2RaySubscription(buf []byte) bool {
	raw := strings.ToLower(strings.TrimSpace(string(buf)))
	if raw == "" {
		return false
	}

	if containsShareScheme(raw) {
		return true
	}

	decoded := strings.ToLower(strings.TrimSpace(string(convert.DecodeBase64([]byte(strings.TrimSpace(string(buf)))))))
	if decoded == "" || decoded == raw {
		return false
	}

	return containsShareScheme(decoded)
}

func containsShareScheme(content string) bool {
	return strings.Contains(content, "vless://") ||
		strings.Contains(content, "vmess://") ||
		strings.Contains(content, "trojan://") ||
		strings.Contains(content, "ss://") ||
		strings.Contains(content, "ssr://") ||
		strings.Contains(content, "hysteria://") ||
		strings.Contains(content, "hysteria2://") ||
		strings.Contains(content, "hy2://") ||
		strings.Contains(content, "tuic://")
}

func convertV2RaySubscriptionToRawConfig(buf []byte) (*config.RawConfig, error) {
	proxies, err := convert.ConvertsV2Ray(buf)
	if err != nil {
		return nil, err
	}

	if len(proxies) == 0 {
		return nil, fmt.Errorf("subscription has no proxies")
	}

	cfg := config.DefaultRawConfig()
	cfg.Proxy = proxies

	proxyNames := make([]string, 0, len(proxies))
	usedNames := make(map[string]struct{}, len(proxies)+4)
	for _, proxy := range proxies {
		name, ok := proxy["name"].(string)
		if !ok {
			continue
		}
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		proxyNames = append(proxyNames, name)
		usedNames[name] = struct{}{}
	}

	if len(proxyNames) == 0 {
		return nil, fmt.Errorf("converted proxies missing names")
	}

	mainGroupName := uniqueSyntheticGroupName("PROXY", usedNames)
	usedNames[mainGroupName] = struct{}{}
	autoGroupName := uniqueSyntheticGroupName("AUTO", usedNames)

	selectProxies := make([]string, 0, len(proxyNames)+2)
	if len(proxyNames) > 1 {
		selectProxies = append(selectProxies, autoGroupName)
	}
	selectProxies = append(selectProxies, "DIRECT")
	selectProxies = append(selectProxies, proxyNames...)

	cfg.ProxyGroup = append(cfg.ProxyGroup, map[string]any{
		"name":    mainGroupName,
		"type":    "select",
		"proxies": selectProxies,
	})

	if len(proxyNames) > 1 {
		cfg.ProxyGroup = append(cfg.ProxyGroup, map[string]any{
			"name":     autoGroupName,
			"type":     "url-test",
			"proxies":  proxyNames,
			"url":      "http://www.gstatic.com/generate_204",
			"interval": 300,
		})
	}

	cfg.Rule = buildSyntheticRules(mainGroupName)

	return cfg, nil
}

func buildSyntheticRules(mainGroupName string) []string {
	return []string{
		"GEOIP,LAN,DIRECT,no-resolve",
		"DOMAIN-SUFFIX,local,DIRECT",
		"IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
		"IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
		"IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
		"IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
		"IP-CIDR,100.64.0.0/10,DIRECT,no-resolve",
		"IP-CIDR6,fc00::/7,DIRECT,no-resolve",
		"IP-CIDR6,fe80::/10,DIRECT,no-resolve",
		"GEOSITE,CN,DIRECT",
		"GEOIP,CN,DIRECT,no-resolve",
		fmt.Sprintf("MATCH,%s", mainGroupName),
	}
}

func uniqueSyntheticGroupName(base string, used map[string]struct{}) string {
	if _, exists := used[base]; !exists {
		return base
	}

	for i := 2; ; i++ {
		candidate := fmt.Sprintf("%s-%d", base, i)
		if _, exists := used[candidate]; !exists {
			return candidate
		}
	}
}
