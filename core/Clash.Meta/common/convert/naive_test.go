package convert

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestConvertsV2RayNaiveHTTPS(t *testing.T) {
	link := "naive+https://demo-user:demo-pass@example.com:443?sni=cdn.example.com&insecure=1&fp=chrome&insecure-concurrency=2#naive-test"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		proxy := proxies[0]
		assert.Equal(t, "naive", proxy["type"])
		assert.Equal(t, "example.com", proxy["server"])
		assert.Equal(t, "443", proxy["port"])
		assert.Equal(t, "demo-user", proxy["username"])
		assert.Equal(t, "demo-pass", proxy["password"])
		assert.Equal(t, "cdn.example.com", proxy["sni"])
		assert.Equal(t, true, proxy["skip-cert-verify"])
		assert.Equal(t, "chrome", proxy["client-fingerprint"])
		assert.Equal(t, 2, proxy["insecure-concurrency"])
	}
}

func TestConvertsV2RayNaivePasswordOnly(t *testing.T) {
	link := "naive+https://only-password@example.org:8443#naive-password-only"

	proxies, err := ConvertsV2Ray([]byte(link))

	assert.NoError(t, err)
	if assert.Len(t, proxies, 1) {
		proxy := proxies[0]
		assert.Equal(t, "naive", proxy["type"])
		assert.Equal(t, "only-password", proxy["password"])
		_, hasUser := proxy["username"]
		assert.False(t, hasUser)
	}
}
