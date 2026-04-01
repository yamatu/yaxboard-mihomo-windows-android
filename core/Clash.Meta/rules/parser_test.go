package rules

import "testing"

func TestParseRuleNormalizesURLLikeDomainPayload(t *testing.T) {
	parsed, err := ParseRule("DOMAIN", "https://yamatu.xyz:7001/", "DIRECT", nil, nil)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if got, want := parsed.Payload(), "yamatu.xyz"; got != want {
		t.Fatalf("unexpected payload: got %q want %q", got, want)
	}
}

func TestParseRuleNormalizesHostPortDomainSuffixPayload(t *testing.T) {
	parsed, err := ParseRule("DOMAIN-SUFFIX", "yamatu.xyz:7001", "DIRECT", nil, nil)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if got, want := parsed.Payload(), "yamatu.xyz"; got != want {
		t.Fatalf("unexpected payload: got %q want %q", got, want)
	}
}

func TestParseRuleKeepsNormalDomainPayload(t *testing.T) {
	parsed, err := ParseRule("DOMAIN", "api.yamatu.xyz", "DIRECT", nil, nil)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if got, want := parsed.Payload(), "api.yamatu.xyz"; got != want {
		t.Fatalf("unexpected payload: got %q want %q", got, want)
	}
}
