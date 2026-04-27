package convert

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// https://v2.hysteria.network/zh/docs/developers/URI-Scheme/
func TestConvertsV2Ray_normal(t *testing.T) {
	hy2test := "hysteria2://letmein@example.com:8443/?insecure=1&obfs=salamander&obfs-password=gawrgura&pinSHA256=deadbeef&sni=real.example.com&up=114&down=514&alpn=h3,h4#hy2test"

	expected := []map[string]interface{}{
		{
			"name":             "hy2test",
			"type":             "hysteria2",
			"server":           "example.com",
			"port":             "8443",
			"sni":              "real.example.com",
			"obfs":             "salamander",
			"obfs-password":    "gawrgura",
			"alpn":             []string{"h3", "h4"},
			"password":         "letmein",
			"up":               "114",
			"down":             "514",
			"skip-cert-verify": true,
			"fingerprint":      "deadbeef",
		},
	}

	proxies, err := ConvertsV2Ray([]byte(hy2test))

	assert.Nil(t, err)
	assert.Equal(t, expected, proxies)
}

func TestConvertsV2Ray_vlessXHTTP(t *testing.T) {
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&type=xhttp&host=example.com&path=%2Ftest&mode=packet-up#xhttp-test"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		proxy := proxies[0]
		assert.Equal(t, "vless", proxy["type"])
		assert.Equal(t, "xhttp", proxy["network"])

		xhttpOpts, ok := proxy["xhttp-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, "packet-up", xhttpOpts["mode"])
			assert.Equal(t, "/test", xhttpOpts["path"])

			headers, ok := xhttpOpts["headers"].(map[string]any)
			if assert.True(t, ok) {
				assert.Equal(t, "example.com", headers["Host"])
			}
		}
	}
}

func TestConvertsV2Ray_vlessXHTTPKeepsPanelEncryptionValue(t *testing.T) {
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&type=xhttp&host=example.com&path=%2Ftest&mode=stream-one&encryption=mlkem768x25519plus.native.600s.rYcGzwIyX6qtzNjOEhFNjayoiFMyjkc6NgOYy002oEk#xhttp-encryption"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		proxy := proxies[0]
		assert.Equal(t, "mlkem768x25519plus.native.600s.rYcGzwIyX6qtzNjOEhFNjayoiFMyjkc6NgOYy002oEk", proxy["encryption"])
		assert.Equal(t, "xhttp", proxy["network"])

		xhttpOpts, ok := proxy["xhttp-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, "stream-one", xhttpOpts["mode"])
			assert.Equal(t, "/test", xhttpOpts["path"])
		}
	}
}

func TestConvertsV2Ray_vlessKeepsPanelEncryptionAndVisionFlow(t *testing.T) {
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&encryption=mlkem768x25519plus.native.600s.rYcGzwIyX6qtzNjOEhFNjayoiFMyjkc6NgOYy002oEk&flow=xtls-rprx-vision#vision-encryption"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		proxy := proxies[0]
		assert.Equal(t, "mlkem768x25519plus.native.600s.rYcGzwIyX6qtzNjOEhFNjayoiFMyjkc6NgOYy002oEk", proxy["encryption"])
		assert.Equal(t, "xtls-rprx-vision", proxy["flow"])
	}
}

func TestConvertsV2Ray_vlessECHQuery(t *testing.T) {
	echConfig := "AAECAw=="
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&ech=" + echConfig + "#ech-query"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		echOpts, ok := proxies[0]["ech-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, true, echOpts["enable"])
			assert.Equal(t, echConfig, echOpts["config"])
		}
	}
}

func TestConvertsV2Ray_vlessECHConfigListQuery(t *testing.T) {
	echConfig := "AAECAw=="
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&echConfigList=" + echConfig + "#ech-config-list"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		echOpts, ok := proxies[0]["ech-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, true, echOpts["enable"])
			assert.Equal(t, echConfig, echOpts["config"])
		}
	}
}

func TestConvertsV2Ray_vlessECHQueryOptions(t *testing.T) {
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&ech=cloudflare-ech.com%2Bhttps%3A%2F%2Fdns.alidns.com%2Fdns-query&echConfigList=https%3A%2F%2Fdns.alidns.com%2Fdns-query&echForceQuery=full#ech-query-options"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		echOpts, ok := proxies[0]["ech-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, true, echOpts["enable"])
			assert.Equal(t, "https://dns.alidns.com/dns-query", echOpts["config-list"])
			assert.Equal(t, "full", echOpts["force-query"])
			assert.Equal(t, "cloudflare-ech.com", echOpts["query-server-name"])
		}
	}
}

func TestConvertsV2Ray_vlessECHFromXrayExtraTLSSettings(t *testing.T) {
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&extra={\"extra\":{\"downloadSettings\":{\"network\":\"xhttp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"example.com\",\"echConfigList\":[\"AAECAw==\"]}}}}#ech-extra"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		echOpts, ok := proxies[0]["ech-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, true, echOpts["enable"])
			assert.Equal(t, "AAECAw==", echOpts["config"])
		}
	}
}

func TestConvertsV2Ray_vlessECHFromNestedXboardSettings(t *testing.T) {
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&extra={\"extra\":{\"downloadSettings\":{\"network\":\"xhttp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"example.com\",\"ech\":{\"enabled\":true,\"config_list\":\"https://dns.alidns.com/dns-query\",\"force_query\":\"full\",\"query_server_name\":\"cloudflare-ech.com\"}}}}}#ech-nested"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		echOpts, ok := proxies[0]["ech-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, true, echOpts["enable"])
			assert.Equal(t, "https://dns.alidns.com/dns-query", echOpts["config-list"])
			assert.Equal(t, "full", echOpts["force-query"])
			assert.Equal(t, "cloudflare-ech.com", echOpts["query-server-name"])
		}
	}
}

func TestConvertsV2Ray_vlessECHFromCombinedXrayTLSSettings(t *testing.T) {
	link := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&extra={\"extra\":{\"downloadSettings\":{\"network\":\"xhttp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"example.com\",\"echConfigList\":[\"cloudflare-ech.com+https://dns.alidns.com/dns-query\"],\"echForceQuery\":\"full\"}}}}#ech-combined"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		echOpts, ok := proxies[0]["ech-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, true, echOpts["enable"])
			assert.Equal(t, "https://dns.alidns.com/dns-query", echOpts["config-list"])
			assert.Equal(t, "full", echOpts["force-query"])
			assert.Equal(t, "cloudflare-ech.com", echOpts["query-server-name"])
		}
	}
}

func TestConvertsV2Ray_vlessSplitHTTP(t *testing.T) {
	link := "vless://33333333-3333-3333-3333-333333333333@example.com:443?security=tls&type=splithttp&host=example.com&path=%2Fsplit#split-http-test"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		proxy := proxies[0]
		assert.Equal(t, "vless", proxy["type"])
		assert.Equal(t, "xhttp", proxy["network"])

		xhttpOpts, ok := proxy["xhttp-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, "/split", xhttpOpts["path"])
		}
	}
}

func TestConvertsV2Ray_vlessXHTTPRawExtraReality(t *testing.T) {
	link := "vless://11111111-1111-1111-1111-111111111111@jpp.yamatu.xyz:2053?encryption=none&security=reality&type=xhttp&extra={\"host\":\"jpp.yamatu.xyz\",\"path\":\"/api/v3/resource\",\"mode\":\"stream-one\",\"extra\":{\"headers\":{\"User-Agent\":\"Mozilla/5.0\"},\"downloadSettings\":{\"address\":\"jpp.yamatu.xyz\",\"port\":2053,\"network\":\"xhttp\",\"security\":\"reality\",\"tlsSettings\":{\"serverName\":\"jpp.yamatu.xyz\",\"alpn\":[\"h2\",\"http/1.1\"],\"allowInsecure\":false},\"realitySettings\":{\"publicKey\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"shortId\":\"abcd\"}}}}#xhttp-reality"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		proxy := proxies[0]
		assert.Equal(t, "vless", proxy["type"])
		assert.Equal(t, "xhttp", proxy["network"])
		assert.Equal(t, true, proxy["tls"])
		assert.Equal(t, "jpp.yamatu.xyz", proxy["servername"])

		realityOpts, ok := proxy["reality-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", realityOpts["public-key"])
			assert.Equal(t, "abcd", realityOpts["short-id"])
		}

		xhttpOpts, ok := proxy["xhttp-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, "/api/v3/resource", xhttpOpts["path"])
			assert.Equal(t, "stream-one", xhttpOpts["mode"])
		}
	}
}

func TestConvertsV2Ray_vlessXHTTPFromExtraWithoutType(t *testing.T) {
	link := "vless://66666666-6666-6666-6666-666666666666@jpp.yamatu.xyz:2053?encryption=none&extra={\"extra\":{\"downloadSettings\":{\"network\":\"xhttp\",\"security\":\"reality\",\"address\":\"jpp.yamatu.xyz\",\"realitySettings\":{\"publicKey\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"shortId\":\"abcd\"},\"xhttpSettings\":{\"path\":\"/api/v3/resource\"}}}}#xhttp-extra-only"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		proxy := proxies[0]
		assert.Equal(t, "vless", proxy["type"])
		assert.Equal(t, "xhttp", proxy["network"])

		realityOpts, ok := proxy["reality-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", realityOpts["public-key"])
			assert.Equal(t, "abcd", realityOpts["short-id"])
		}

		xhttpOpts, ok := proxy["xhttp-opts"].(map[string]any)
		if assert.True(t, ok) {
			assert.Equal(t, "/api/v3/resource", xhttpOpts["path"])
		}
	}
}
