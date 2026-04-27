package outbound

import "testing"

func TestSplitECHConfigListValue(t *testing.T) {
	queryName, configList := splitECHConfigListValue("cloudflare-ech.com+https://dns.alidns.com/dns-query")

	if queryName != "cloudflare-ech.com" {
		t.Fatalf("query name = %q", queryName)
	}
	if configList != "https://dns.alidns.com/dns-query" {
		t.Fatalf("config list = %q", configList)
	}
}
