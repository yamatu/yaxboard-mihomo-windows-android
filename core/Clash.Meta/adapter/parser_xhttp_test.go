package adapter

import (
	"strings"
	"testing"

	"github.com/metacubex/mihomo/common/convert"
)

func TestParseProxyVlessXHTTP(t *testing.T) {
	mapping := map[string]any{
		"name":       "xhttp-vless",
		"type":       "vless",
		"server":     "example.com",
		"port":       443,
		"uuid":       "11111111-1111-1111-1111-111111111111",
		"tls":        true,
		"servername": "example.com",
		"network":    "xhttp",
		"xhttp-opts": map[string]any{
			"host": []any{"cdn.example.com"},
			"path": []any{"/xhttp"},
			"mode": "packet-up",
			"headers": map[string]any{
				"User-Agent": []any{"Mozilla/5.0"},
			},
			"scMaxEachPostBytes": 1048576,
		},
	}

	proxy, err := ParseProxy(mapping)
	if err != nil {
		t.Fatalf("ParseProxy(vless xhttp) failed: %v", err)
	}
	if proxy == nil {
		t.Fatal("ParseProxy(vless xhttp) returned nil proxy")
	}
}

func TestParseProxyVmessXHTTP(t *testing.T) {
	mapping := map[string]any{
		"name":       "xhttp-vmess",
		"type":       "vmess",
		"server":     "example.com",
		"port":       443,
		"uuid":       "22222222-2222-2222-2222-222222222222",
		"alterId":    0,
		"cipher":     "auto",
		"tls":        true,
		"servername": "example.com",
		"network":    "xhttp",
		"xhttp-opts": map[string]any{
			"host": "cdn2.example.com",
			"path": "/vmess-xhttp",
			"mode": "auto",
		},
	}

	proxy, err := ParseProxy(mapping)
	if err != nil {
		t.Fatalf("ParseProxy(vmess xhttp) failed: %v", err)
	}
	if proxy == nil {
		t.Fatal("ParseProxy(vmess xhttp) returned nil proxy")
	}
}

func TestParseProxyTrojanXHTTP(t *testing.T) {
	mapping := map[string]any{
		"name":     "xhttp-trojan",
		"type":     "trojan",
		"server":   "example.com",
		"port":     443,
		"password": "test-password",
		"sni":      "example.com",
		"network":  "xhttp",
		"xhttp-opts": map[string]any{
			"path": "/trojan-xhttp",
			"mode": "packet-up",
		},
	}

	proxy, err := ParseProxy(mapping)
	if err != nil {
		t.Fatalf("ParseProxy(trojan xhttp) failed: %v", err)
	}
	if proxy == nil {
		t.Fatal("ParseProxy(trojan xhttp) returned nil proxy")
	}
}

func TestParseProxyVlessXHTTPReality(t *testing.T) {
	mapping := map[string]any{
		"name":       "xhttp-vless-reality",
		"type":       "vless",
		"server":     "jpp.yamatu.xyz",
		"port":       2053,
		"uuid":       "44444444-4444-4444-4444-444444444444",
		"tls":        true,
		"servername": "jpp.yamatu.xyz",
		"network":    "xhttp",
		"reality-opts": map[string]any{
			"public-key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
			"short-id":   "abcd",
		},
		"xhttp-opts": map[string]any{
			"host": "jpp.yamatu.xyz",
			"path": "/api/v3/resource",
			"mode": "stream-one",
			"headers": map[string]any{
				"User-Agent": "Mozilla/5.0",
			},
		},
	}

	proxy, err := ParseProxy(mapping)
	if err != nil {
		t.Fatalf("ParseProxy(vless xhttp+reality) failed: %v", err)
	}
	if proxy == nil {
		t.Fatal("ParseProxy(vless xhttp+reality) returned nil proxy")
	}
}

func TestParseProxyVlessXHTTPFromExtraOnly(t *testing.T) {
	mapping := map[string]any{
		"name":   "xhttp-vless-extra-only",
		"type":   "vless",
		"server": "jpp.yamatu.xyz",
		"port":   2053,
		"uuid":   "55555555-5555-5555-5555-555555555555",
		"xhttp-opts": map[string]any{
			"host": "jpp.yamatu.xyz",
			"path": "/api/v3/resource",
			"mode": "stream-one",
			"extra": map[string]any{
				"headers": map[string]any{
					"User-Agent": "Mozilla/5.0",
				},
				"downloadSettings": map[string]any{
					"address":  "jpp.yamatu.xyz",
					"network":  "xhttp",
					"security": "reality",
					"tlsSettings": map[string]any{
						"serverName":    "jpp.yamatu.xyz",
						"allowInsecure": false,
						"alpn":          []any{"h2", "http/1.1"},
					},
					"realitySettings": map[string]any{
						"publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
						"shortId":   "abcd",
					},
				},
			},
		},
	}

	proxy, err := ParseProxy(mapping)
	if err != nil {
		t.Fatalf("ParseProxy(vless xhttp from extra) failed: %v", err)
	}
	if proxy == nil {
		t.Fatal("ParseProxy(vless xhttp from extra) returned nil proxy")
	}
}

func TestParseProxyFromProvidedVlessXHTTPLines(t *testing.T) {
	line1 := "vless://db17b444-a125-4bb7-961d-5a2305eac06b@yg1.ygkkk.dpdns.org:443?encryption=mlkem768x25519plus.random.0rtt.-kQZdekBfxssneSGh10e1CI2379hrp7IJjQ1P3npSjA&security=tls&sni=R65TU.cnmcnmcnmcnmcnm.cfd&fp=safari&insecure=0&allowInsecure=0&type=xhttp&host=hk1.cnmcnmcnmcnmcnm.cfd&path=%2Fapi%2Fv3%2Fresource%2F8f9a2c4d-6e7b-4f1a-9d3e-5c8b0a1f2e3d%2Fupdate%2Fcheck&mode=stream-one&extra=%7B%22padding%22%3A%22true%22%2C%22headers%22%3A%7B%22User-Agent%22%3A%22Mozilla%2F5.0%2B%28Windows%2BNT%2B10.0%3B%2BWin64%3B%2Bx64%29%2BAppleWebKit%2F537.36%2B%28KHTML%2C%2Blike%2BGecko%29%2BChrome%2F132.0.0.0%2BSafari%2F537.36%2BEdg%2F132.0.0.0%22%2C%22Accept%22%3A%22text%2Fhtml%2Capplication%2Fxhtml%2Bxml%2Capplication%2Fxml%3Bq%3D0.9%2Cimage%2Favif%2Cimage%2Fwebp%2Cimage%2Fapng%2C%2A%2F%2A%3Bq%3D0.8%22%2C%22Accept-Language%22%3A%22zh-CN%2Czh%3Bq%3D0.9%2Cen%3Bq%3D0.8%22%2C%22Accept-Encoding%22%3A%22gzip%2C%2Bdeflate%2C%2Bbr%22%2C%22Connection%22%3A%22keep-alive%22%7D%7D#%F0%9F%87%AD%F0%9F%87%B0%E9%A6%99%E6%B8%AF%20%7C%20CF%E5%85%A5%E5%8F%A3"
	line2 := "vless://db17b444-a125-4bb7-961d-5a2305eac06b@b4h8y0h2j7-jp-2.fasttransitss.pp.ua:42229?encryption=mlkem768x25519plus.random.0rtt.rYcGzwIyX6qtzNjOEhFNjayoiFMyjkc6NgOYy002oEk&security=reality&sni=apple.com&fp=safari&pbk=Mk7bw68hoh1llWoVkS3WhvyrH3C4IIRFJs1vGGelPWQ&sid=372be4f9&type=xhttp&path=%2F8f9a2c4d-6e7b-4f1a-9d3e-5c8b0a1f2e3d%2Fapi%2Fv3%2Fresource&mode=stream-one&extra=%7B%22headers%22%3A%7B%22User-Agent%22%3A%22Mozilla%2F5.0%2B%28Windows%2BNT%2B10.0%3B%2BWin64%3B%2Bx64%29%2BAppleWebKit%2F537.36%2B%28KHTML%2C%2Blike%2BGecko%29%2BChrome%2F132.0.0.0%2BSafari%2F537.36%22%2C%22Accept%22%3A%22text%2Fhtml%2Capplication%2Fxhtml%2Bxml%2Capplication%2Fxml%3Bq%3D0.9%2Cimage%2Favif%2Cimage%2Fwebp%2C%2A%2F%2A%3Bq%3D0.8%22%2C%22Accept-Language%22%3A%22zh-CN%2Czh%3Bq%3D0.9%2Cen%3Bq%3D0.8%22%7D%7D#%F0%9F%87%AD%F0%9F%87%B0%E9%A6%99%E6%B8%AF%20%7C%20%E6%97%A5%E6%9C%AC%E5%85%A5%E5%8F%A3"

	proxies, err := convert.ConvertsV2Ray([]byte(strings.Join([]string{line1, line2}, "\n")))
	if err != nil {
		t.Fatalf("ConvertsV2Ray failed: %v", err)
	}
	if len(proxies) != 2 {
		t.Fatalf("expected 2 proxies, got %d", len(proxies))
	}

	for i, mapping := range proxies {
		proxy, err := ParseProxy(mapping)
		if err != nil {
			t.Fatalf("ParseProxy failed at index %d: %v, mapping=%v", i, err, mapping)
		}
		if proxy == nil {
			t.Fatalf("ParseProxy returned nil at index %d", i)
		}
	}
}
