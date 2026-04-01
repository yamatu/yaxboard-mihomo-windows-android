package convert

import (
	"net/url"
	"strconv"
	"strings"
)

func parseNaiveShareLink(line string, scheme string, names map[string]int) (map[string]any, error) {
	parsedURL, err := url.Parse(line)
	if err != nil {
		return nil, err
	}

	port := parsedURL.Port()
	if port == "" {
		port = "443"
	}

	nameHint := strings.TrimSpace(parsedURL.Fragment)
	if nameHint == "" {
		nameHint = strings.TrimSpace(parsedURL.Hostname())
	}

	naive := map[string]any{
		"name":   uniqueName(names, nameHint),
		"type":   "naive",
		"server": parsedURL.Hostname(),
		"port":   port,
	}

	if parsedURL.Hostname() == "" {
		return nil, strconv.ErrSyntax
	}

	if password, ok := parsedURL.User.Password(); ok {
		naive["username"] = parsedURL.User.Username()
		naive["password"] = password
	} else if rawPassword := strings.TrimSpace(parsedURL.User.Username()); rawPassword != "" {
		naive["password"] = rawPassword
	}

	query := parsedURL.Query()

	if sni := firstNonEmpty(query.Get("sni"), query.Get("servername"), query.Get("peer")); sni != "" {
		naive["sni"] = sni
	}

	if clientFingerprint := firstNonEmpty(query.Get("fp"), query.Get("client-fingerprint")); clientFingerprint != "" {
		naive["client-fingerprint"] = clientFingerprint
	}

	if rawInsecure := firstNonEmpty(query.Get("allowInsecure"), query.Get("insecure")); rawInsecure != "" {
		if insecure, ok := valueToBool(rawInsecure); ok {
			naive["skip-cert-verify"] = insecure
		}
	}

	if insecureConcurrency := strings.TrimSpace(query.Get("insecure-concurrency")); insecureConcurrency != "" {
		if value, err := strconv.Atoi(insecureConcurrency); err == nil && value > 0 {
			naive["insecure-concurrency"] = value
		}
	}

	if network := normalizeNaiveNetwork(scheme, query.Get("network"), query.Get("type")); network != "" {
		naive["network"] = network
	}

	if headers := parseNaiveHeaders(firstNonEmpty(query.Get("extra-headers"), query.Get("extra_headers"), query.Get("headers"))); len(headers) > 0 {
		naive["headers"] = headers
	}

	return naive, nil
}

func normalizeNaiveNetwork(values ...string) string {
	for _, value := range values {
		normalized := strings.ToLower(strings.TrimSpace(value))
		switch normalized {
		case "", "naive", "https", "h2", "http2":
			continue
		case "naive+quic", "naive+http3", "quic", "h3", "http3":
			return "quic"
		}
	}
	return ""
}

func parseNaiveHeaders(raw string) map[string]string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}

	if headerMap := valueToStringMap(decodeJSONMap(raw)); len(headerMap) > 0 {
		return headerMap
	}

	if unescaped, err := url.QueryUnescape(raw); err == nil {
		if headerMap := valueToStringMap(decodeJSONMap(unescaped)); len(headerMap) > 0 {
			return headerMap
		}
	}

	return nil
}
