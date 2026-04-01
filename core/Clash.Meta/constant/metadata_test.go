package constant

import "testing"

func TestRuleHostNormalizesHostPort(t *testing.T) {
	metadata := &Metadata{Host: "yamatu.xyz:7001"}

	if got, want := metadata.RuleHost(), "yamatu.xyz"; got != want {
		t.Fatalf("unexpected rule host: got %q want %q", got, want)
	}
}

func TestRuleHostNormalizesSniffHostPortAndCase(t *testing.T) {
	metadata := &Metadata{
		Host:      "ignored.example",
		SniffHost: "YaMatu.XyZ:7001",
	}

	if got, want := metadata.RuleHost(), "yamatu.xyz"; got != want {
		t.Fatalf("unexpected rule host: got %q want %q", got, want)
	}
}

func TestRuleHostTrimsTrailingDot(t *testing.T) {
	metadata := &Metadata{Host: "yamatu.xyz."}

	if got, want := metadata.RuleHost(), "yamatu.xyz"; got != want {
		t.Fatalf("unexpected rule host: got %q want %q", got, want)
	}
}

func TestRuleHostNormalizesURLLikeHost(t *testing.T) {
	metadata := &Metadata{Host: "https://yamatu.xyz:7001/path?q=1"}

	if got, want := metadata.RuleHost(), "yamatu.xyz"; got != want {
		t.Fatalf("unexpected rule host: got %q want %q", got, want)
	}
}

func TestRuleHostNormalizesQuotedHost(t *testing.T) {
	metadata := &Metadata{Host: "\"yamatu.xyz:7001\""}

	if got, want := metadata.RuleHost(), "yamatu.xyz"; got != want {
		t.Fatalf("unexpected rule host: got %q want %q", got, want)
	}
}
