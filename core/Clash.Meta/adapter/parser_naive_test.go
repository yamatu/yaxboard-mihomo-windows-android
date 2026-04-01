package adapter

import (
	"strings"
	"testing"

	"github.com/metacubex/mihomo/common/convert"
)

func TestParseProxyNaive(t *testing.T) {
	mapping := map[string]any{
		"name":                 "naive-h2",
		"type":                 "naive",
		"server":               "example.com",
		"port":                 443,
		"username":             "demo-user",
		"password":             "demo-pass",
		"sni":                  "cdn.example.com",
		"skip-cert-verify":     true,
		"client-fingerprint":   "chrome",
		"insecure-concurrency": 2,
		"headers": map[string]any{
			"User-Agent": "Mozilla/5.0",
		},
	}

	proxy, err := ParseProxy(mapping)
	if err != nil {
		t.Fatalf("ParseProxy(naive) failed: %v", err)
	}
	if proxy == nil {
		t.Fatal("ParseProxy(naive) returned nil proxy")
	}
	if proxy.Adapter().Type().String() != "Naive" {
		t.Fatalf("unexpected proxy type: %s", proxy.Adapter().Type().String())
	}
}

func TestParseProxyNaiveQUICRejected(t *testing.T) {
	mapping := map[string]any{
		"name":     "naive-quic",
		"type":     "naive",
		"server":   "example.com",
		"port":     443,
		"password": "demo-pass",
		"network":  "quic",
	}

	_, err := ParseProxy(mapping)
	if err == nil {
		t.Fatal("ParseProxy(naive quic) expected error, got nil")
	}
	if !strings.Contains(strings.ToLower(err.Error()), "quic") {
		t.Fatalf("expected quic-related error, got: %v", err)
	}
}

func TestParseProxyFromNaiveShareLines(t *testing.T) {
	line1 := "naive+https://demo-user:demo-pass@example.com:443?sni=cdn.example.com&fp=chrome&insecure=1#naive-share"

	proxies, err := convert.ConvertsV2Ray([]byte(line1))
	if err != nil {
		t.Fatalf("ConvertsV2Ray failed: %v", err)
	}
	if len(proxies) != 1 {
		t.Fatalf("expected 1 proxy, got %d", len(proxies))
	}

	proxy, err := ParseProxy(proxies[0])
	if err != nil {
		t.Fatalf("ParseProxy failed: %v, mapping=%v", err, proxies[0])
	}
	if proxy == nil {
		t.Fatal("ParseProxy returned nil proxy")
	}
}
