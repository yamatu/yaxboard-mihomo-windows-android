package provider

import (
	"strings"
	"testing"
)

func TestNewProxiesParserWithProvidedXHTTPLines(t *testing.T) {
	line1 := "vless://db17b444-a125-4bb7-961d-5a2305eac06b@yg1.ygkkk.dpdns.org:443?encryption=mlkem768x25519plus.random.0rtt.-kQZdekBfxssneSGh10e1CI2379hrp7IJjQ1P3npSjA&security=tls&sni=R65TU.cnmcnmcnmcnmcnm.cfd&fp=safari&insecure=0&allowInsecure=0&type=xhttp&host=hk1.cnmcnmcnmcnmcnm.cfd&path=%2Fapi%2Fv3%2Fresource%2F8f9a2c4d-6e7b-4f1a-9d3e-5c8b0a1f2e3d%2Fupdate%2Fcheck&mode=stream-one&extra=%7B%22padding%22%3A%22true%22%2C%22headers%22%3A%7B%22User-Agent%22%3A%22Mozilla%2F5.0%2B%28Windows%2BNT%2B10.0%3B%2BWin64%3B%2Bx64%29%2BAppleWebKit%2F537.36%2B%28KHTML%2C%2Blike%2BGecko%29%2BChrome%2F132.0.0.0%2BSafari%2F537.36%2BEdg%2F132.0.0.0%22%2C%22Accept%22%3A%22text%2Fhtml%2Capplication%2Fxhtml%2Bxml%2Capplication%2Fxml%3Bq%3D0.9%2Cimage%2Favif%2Cimage%2Fwebp%2Cimage%2Fapng%2C%2A%2F%2A%3Bq%3D0.8%22%2C%22Accept-Language%22%3A%22zh-CN%2Czh%3Bq%3D0.9%2Cen%3Bq%3D0.8%22%2C%22Accept-Encoding%22%3A%22gzip%2C%2Bdeflate%2C%2Bbr%22%2C%22Connection%22%3A%22keep-alive%22%7D%7D#%F0%9F%87%AD%F0%9F%87%B0%E9%A6%99%E6%B8%AF%20%7C%20CF%E5%85%A5%E5%8F%A3"
	line2 := "vless://db17b444-a125-4bb7-961d-5a2305eac06b@b4h8y0h2j7-jp-2.fasttransitss.pp.ua:42229?encryption=mlkem768x25519plus.random.0rtt.rYcGzwIyX6qtzNjOEhFNjayoiFMyjkc6NgOYy002oEk&security=reality&sni=apple.com&fp=safari&pbk=Mk7bw68hoh1llWoVkS3WhvyrH3C4IIRFJs1vGGelPWQ&sid=372be4f9&type=xhttp&path=%2F8f9a2c4d-6e7b-4f1a-9d3e-5c8b0a1f2e3d%2Fapi%2Fv3%2Fresource&mode=stream-one&extra=%7B%22headers%22%3A%7B%22User-Agent%22%3A%22Mozilla%2F5.0%2B%28Windows%2BNT%2B10.0%3B%2BWin64%3B%2Bx64%29%2BAppleWebKit%2F537.36%2B%28KHTML%2C%2Blike%2BGecko%29%2BChrome%2F132.0.0.0%2BSafari%2F537.36%22%2C%22Accept%22%3A%22text%2Fhtml%2Capplication%2Fxhtml%2Bxml%2Capplication%2Fxml%3Bq%3D0.9%2Cimage%2Favif%2Cimage%2Fwebp%2C%2A%2F%2A%3Bq%3D0.8%22%2C%22Accept-Language%22%3A%22zh-CN%2Czh%3Bq%3D0.9%2Cen%3Bq%3D0.8%22%7D%7D#%F0%9F%87%AD%F0%9F%87%B0%E9%A6%99%E6%B8%AF%20%7C%20%E6%97%A5%E6%9C%AC%E5%85%A5%E5%8F%A3"

	parser, err := NewProxiesParser("", "", "", "", OverrideSchema{})
	if err != nil {
		t.Fatalf("NewProxiesParser failed: %v", err)
	}

	proxies, err := parser([]byte(strings.Join([]string{line1, line2}, "\n")))
	if err != nil {
		t.Fatalf("parser failed: %v", err)
	}

	if len(proxies) != 2 {
		t.Fatalf("expected 2 proxies, got %d", len(proxies))
	}
}
