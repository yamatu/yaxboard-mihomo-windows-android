package main

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestParseRawConfigWithSubscriptionCompat_Base64V2Ray(t *testing.T) {
	rawLinks := strings.Join([]string{
		"vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&type=xhttp&host=example.com&path=%2Fapi&mode=packet-up#xhttp-1",
		"vless://22222222-2222-2222-2222-222222222222@example.net:443?security=reality&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=abcd&type=xhttp&path=%2Fresource#xhttp-2",
	}, "\n")

	encoded := base64.StdEncoding.EncodeToString([]byte(rawLinks))

	rawCfg, err := parseRawConfigWithSubscriptionCompat([]byte(encoded))
	if err != nil {
		t.Fatalf("parseRawConfigWithSubscriptionCompat returned error: %v", err)
	}

	if len(rawCfg.Proxy) != 2 {
		t.Fatalf("expected 2 proxies, got %d", len(rawCfg.Proxy))
	}

	if len(rawCfg.ProxyGroup) == 0 {
		t.Fatalf("expected generated proxy groups, got none")
	}

	if len(rawCfg.Rule) == 0 {
		t.Fatalf("expected generated rules, got none")
	}

	lastRule := rawCfg.Rule[len(rawCfg.Rule)-1]
	if !strings.HasPrefix(lastRule, "MATCH,") {
		t.Fatalf("expected trailing MATCH rule, got %v", rawCfg.Rule)
	}

	hasGeoIPCN := false
	for _, rule := range rawCfg.Rule {
		if strings.EqualFold(rule, "GEOIP,CN,DIRECT,no-resolve") {
			hasGeoIPCN = true
			break
		}
	}
	if !hasGeoIPCN {
		t.Fatalf("expected GEOIP,CN direct rule, got %v", rawCfg.Rule)
	}
}
