package provider

import (
	"testing"
)

func TestNewProxiesParserWithNaiveShareLine(t *testing.T) {
	line := "naive+https://demo-user:demo-pass@example.com:443?sni=cdn.example.com&fp=chrome&insecure=1#naive-provider"

	parser, err := NewProxiesParser("", "", "", "", OverrideSchema{})
	if err != nil {
		t.Fatalf("NewProxiesParser failed: %v", err)
	}

	proxies, err := parser([]byte(line))
	if err != nil {
		t.Fatalf("parser failed: %v", err)
	}

	if len(proxies) != 1 {
		t.Fatalf("expected 1 proxy, got %d", len(proxies))
	}
}
