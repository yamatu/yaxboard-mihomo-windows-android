package outbound

import (
	"bytes"
	"context"
	"fmt"
	"net"
	"net/netip"
	"regexp"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/component/resolver"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/transport/socks5"
)

func serializesSocksAddr(metadata *C.Metadata) []byte {
	var buf [][]byte
	addrType := metadata.AddrType()
	p := uint(metadata.DstPort)
	port := []byte{uint8(p >> 8), uint8(p & 0xff)}
	switch addrType {
	case C.AtypDomainName:
		lenM := uint8(len(metadata.Host))
		host := []byte(metadata.Host)
		buf = [][]byte{{socks5.AtypDomainName, lenM}, host, port}
	case C.AtypIPv4:
		host := metadata.DstIP.AsSlice()
		buf = [][]byte{{socks5.AtypIPv4}, host, port}
	case C.AtypIPv6:
		host := metadata.DstIP.AsSlice()
		buf = [][]byte{{socks5.AtypIPv6}, host, port}
	}
	return bytes.Join(buf, nil)
}

func resolveUDPAddr(ctx context.Context, network, address string, prefer C.DNSPrefer) (*net.UDPAddr, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	var ip netip.Addr
	switch prefer {
	case C.IPv4Only:
		ip, err = resolver.ResolveIPv4WithResolver(ctx, host, resolver.ProxyServerHostResolver)
	case C.IPv6Only:
		ip, err = resolver.ResolveIPv6WithResolver(ctx, host, resolver.ProxyServerHostResolver)
	case C.IPv6Prefer:
		ip, err = resolver.ResolveIPPrefer6WithResolver(ctx, host, resolver.ProxyServerHostResolver)
	default:
		ip, err = resolver.ResolveIPWithResolver(ctx, host, resolver.ProxyServerHostResolver)
	}

	if err != nil {
		return nil, err
	}

	ip, port = resolver.LookupIP4P(ip, port)
	return net.ResolveUDPAddr(network, net.JoinHostPort(ip.String(), port))
}

func safeConnClose(c net.Conn, err error) {
	if err != nil && c != nil {
		_ = c.Close()
	}
}

func firstString(v any) string {
	switch value := v.(type) {
	case nil:
		return ""
	case string:
		return strings.TrimSpace(value)
	case []string:
		for _, item := range value {
			if s := strings.TrimSpace(item); s != "" {
				return s
			}
		}
		return ""
	case []any:
		for _, item := range value {
			if s := firstString(item); s != "" {
				return s
			}
		}
		return ""
	default:
		s := strings.TrimSpace(fmt.Sprint(value))
		if strings.EqualFold(s, "<nil>") {
			return ""
		}
		return s
	}
}

func firstNonEmptyString(values ...string) string {
	for _, value := range values {
		if s := strings.TrimSpace(value); s != "" {
			return s
		}
	}
	return ""
}

func httpUpgradeNetworkAlias(network string) bool {
	network = strings.ToLower(strings.TrimSpace(network))
	switch network {
	case "httpupgrade", "http-upgrade":
		return true
	default:
		return false
	}
}

func splitHTTPNetworkAlias(network string) bool {
	network = strings.ToLower(strings.TrimSpace(network))
	switch network {
	case "xhttp", "splithttp", "split-http":
		return true
	default:
		return false
	}
}

func xhttpNetworkAlias(network string) bool {
	return splitHTTPNetworkAlias(network) || httpUpgradeNetworkAlias(network)
}

type xhttpHints struct {
	Network          string
	Security         string
	Host             string
	Path             string
	Mode             string
	Headers          map[string]string
	ServerName       string
	ALPN             []string
	AllowInsecure    *bool
	RealityPublicKey string
	RealityShortID   string
	Fingerprint      string
}

func (h xhttpHints) hasAny() bool {
	return h.Network != "" || h.Host != "" || h.Path != "" || h.Mode != "" || len(h.Headers) > 0 || h.ServerName != "" || len(h.ALPN) > 0 || h.AllowInsecure != nil || h.RealityPublicKey != "" || h.RealityShortID != "" || h.Fingerprint != "" || h.Security != ""
}

func toMapAny(v any) map[string]any {
	if v == nil {
		return nil
	}
	m, ok := v.(map[string]any)
	if !ok {
		return nil
	}
	return m
}

func toStringSlice(v any) []string {
	result := make([]string, 0)
	switch value := v.(type) {
	case []string:
		for _, item := range value {
			if s := strings.TrimSpace(item); s != "" {
				result = append(result, s)
			}
		}
	case []any:
		for _, item := range value {
			if s := firstString(item); s != "" {
				result = append(result, s)
			}
		}
	case string:
		for _, item := range strings.Split(value, ",") {
			if s := strings.TrimSpace(item); s != "" {
				result = append(result, s)
			}
		}
	}
	return result
}

func toBool(v any) (*bool, bool) {
	switch value := v.(type) {
	case bool:
		return &value, true
	case string:
		if value == "" {
			return nil, false
		}
		parsed, err := strconv.ParseBool(value)
		if err != nil {
			return nil, false
		}
		return &parsed, true
	case float64:
		parsed := value != 0
		return &parsed, true
	case int:
		parsed := value != 0
		return &parsed, true
	case int64:
		parsed := value != 0
		return &parsed, true
	default:
		return nil, false
	}
}

func mergeHeaderMap(target map[string]string, source map[string]any) {
	if target == nil || source == nil {
		return
	}
	for key, rawValue := range source {
		if strings.TrimSpace(key) == "" {
			continue
		}
		if strings.TrimSpace(target[key]) != "" {
			continue
		}
		value := firstString(rawValue)
		if value == "" {
			continue
		}
		target[key] = value
	}
}

func extractXHTTPHints(xhttpOpts *XHTTPOptions) xhttpHints {
	hints := xhttpHints{
		Headers: map[string]string{},
	}
	if xhttpOpts == nil {
		return hints
	}

	hints.Host = firstString(xhttpOpts.Host)
	hints.Path = firstString(xhttpOpts.Path)
	hints.Mode = firstString(xhttpOpts.Mode)
	mergeHeaderMap(hints.Headers, xhttpOpts.Headers)

	extra := xhttpOpts.Extra
	if extra == nil {
		return hints
	}

	mergeHeaderMap(hints.Headers, toMapAny(extra["headers"]))

	downloadSettings := toMapAny(extra["downloadSettings"])
	if downloadSettings == nil {
		return hints
	}

	hints.Network = strings.ToLower(firstString(downloadSettings["network"]))
	hints.Security = strings.ToLower(firstString(downloadSettings["security"]))

	if hints.Host == "" {
		hints.Host = firstString(downloadSettings["address"])
	}
	if hints.Path == "" {
		hints.Path = firstString(downloadSettings["path"])
	}
	if hints.Mode == "" {
		hints.Mode = firstString(downloadSettings["mode"])
	}

	tlsSettings := toMapAny(downloadSettings["tlsSettings"])
	if tlsSettings != nil {
		hints.ServerName = firstNonEmptyString(hints.ServerName, firstString(tlsSettings["serverName"]))
		if len(hints.ALPN) == 0 {
			hints.ALPN = toStringSlice(tlsSettings["alpn"])
		}
		if hints.AllowInsecure == nil {
			if allowInsecure, ok := toBool(tlsSettings["allowInsecure"]); ok {
				hints.AllowInsecure = allowInsecure
			}
		}
		hints.Fingerprint = firstNonEmptyString(hints.Fingerprint, firstString(tlsSettings["fingerprint"]))
	}

	xhttpSettings := toMapAny(downloadSettings["xhttpSettings"])
	if xhttpSettings != nil {
		if hints.Host == "" {
			hints.Host = firstString(xhttpSettings["host"])
		}
		if hints.Path == "" {
			hints.Path = firstString(xhttpSettings["path"])
		}
		if hints.Mode == "" {
			hints.Mode = firstString(xhttpSettings["mode"])
		}
		mergeHeaderMap(hints.Headers, toMapAny(xhttpSettings["headers"]))
	}

	realitySettings := toMapAny(downloadSettings["realitySettings"])
	if realitySettings != nil {
		hints.Security = firstNonEmptyString(hints.Security, "reality")
		hints.RealityPublicKey = firstString(realitySettings["publicKey"])
		hints.RealityShortID = firstString(realitySettings["shortId"])
		hints.ServerName = firstNonEmptyString(hints.ServerName, firstString(realitySettings["serverName"]))
		hints.Fingerprint = firstNonEmptyString(hints.Fingerprint, firstString(realitySettings["fingerprint"]))
	}

	return hints
}

func normalizeNetworkWithHints(network string, wsOpts *WSOptions, xhttpOpts *XHTTPOptions, hints xhttpHints) string {
	network = strings.ToLower(strings.TrimSpace(network))
	if network == "" && hints.Network != "" {
		network = strings.ToLower(strings.TrimSpace(hints.Network))
	}
	if network == "" && xhttpOpts != nil {
		if firstString(xhttpOpts.Host) != "" || firstString(xhttpOpts.Path) != "" || strings.TrimSpace(xhttpOpts.Mode) != "" || len(xhttpOpts.Headers) > 0 || len(xhttpOpts.Extra) > 0 {
			network = "xhttp"
		}
	}

	if splitHTTPNetworkAlias(network) {
		if xhttpOpts != nil {
			if firstString(xhttpOpts.Host) == "" && hints.Host != "" {
				xhttpOpts.Host = hints.Host
			}

			if firstString(xhttpOpts.Path) == "" {
				if hints.Path != "" {
					xhttpOpts.Path = hints.Path
				} else {
					xhttpOpts.Path = "/"
				}
			}

			if strings.TrimSpace(xhttpOpts.Mode) == "" && hints.Mode != "" {
				xhttpOpts.Mode = hints.Mode
			}

			if xhttpOpts.Headers == nil {
				xhttpOpts.Headers = map[string]any{}
			}

			if host := firstString(xhttpOpts.Host); host != "" {
				if strings.TrimSpace(firstString(xhttpOpts.Headers["Host"])) == "" {
					xhttpOpts.Headers["Host"] = host
				}
			}

			for key, value := range hints.Headers {
				if strings.TrimSpace(key) == "" || strings.TrimSpace(value) == "" {
					continue
				}
				if strings.TrimSpace(firstString(xhttpOpts.Headers[key])) == "" {
					xhttpOpts.Headers[key] = value
				}
			}
		}

		return "xhttp"
	}

	if !httpUpgradeNetworkAlias(network) {
		return network
	}

	if wsOpts != nil {
		if wsOpts.Path == "" {
			if hints.Path != "" {
				wsOpts.Path = hints.Path
			} else {
				wsOpts.Path = "/"
			}
		}

		if wsOpts.Headers == nil {
			wsOpts.Headers = map[string]string{}
		}

		host := hints.Host
		if host != "" && strings.TrimSpace(wsOpts.Headers["Host"]) == "" {
			wsOpts.Headers["Host"] = host
		}

		for key, value := range hints.Headers {
			if strings.TrimSpace(key) == "" || strings.TrimSpace(value) == "" {
				continue
			}
			if strings.TrimSpace(wsOpts.Headers[key]) == "" {
				wsOpts.Headers[key] = value
			}
		}

		if strings.EqualFold(strings.TrimSpace(hints.Mode), "packet-up") {
			wsOpts.V2rayHttpUpgradeFastOpen = true
		}

		wsOpts.V2rayHttpUpgrade = true
	}

	return "ws"
}

func normalizeWSNetworkWithHints(network string, wsOpts *WSOptions, hints xhttpHints) string {
	return normalizeNetworkWithHints(network, wsOpts, nil, hints)
}

func normalizeWSNetwork(network string, wsOpts *WSOptions, xhttpOpts *XHTTPOptions) string {
	hints := extractXHTTPHints(xhttpOpts)
	return normalizeNetworkWithHints(network, wsOpts, xhttpOpts, hints)
}

func applyXHTTPHintsToVless(option *VlessOption, hints xhttpHints) {
	if option == nil || !hints.hasAny() {
		return
	}

	if !option.TLS && (strings.HasSuffix(hints.Security, "tls") || hints.Security == "reality") {
		option.TLS = true
	}
	if option.ServerName == "" {
		option.ServerName = firstNonEmptyString(hints.ServerName, hints.Host)
	}
	if len(option.ALPN) == 0 && len(hints.ALPN) > 0 {
		option.ALPN = append([]string{}, hints.ALPN...)
	}
	if !option.SkipCertVerify && hints.AllowInsecure != nil {
		option.SkipCertVerify = *hints.AllowInsecure
	}
	if option.Fingerprint == "" {
		option.Fingerprint = hints.Fingerprint
	}
	if option.RealityOpts.PublicKey == "" {
		option.RealityOpts.PublicKey = hints.RealityPublicKey
	}
	if option.RealityOpts.ShortID == "" {
		option.RealityOpts.ShortID = hints.RealityShortID
	}
	if option.ClientFingerprint == "" && option.RealityOpts.PublicKey != "" {
		option.ClientFingerprint = "chrome"
	}
}

func applyXHTTPHintsToVmess(option *VmessOption, hints xhttpHints) {
	if option == nil || !hints.hasAny() {
		return
	}

	if !option.TLS && (strings.HasSuffix(hints.Security, "tls") || hints.Security == "reality") {
		option.TLS = true
	}
	if option.ServerName == "" {
		option.ServerName = firstNonEmptyString(hints.ServerName, hints.Host)
	}
	if len(option.ALPN) == 0 && len(hints.ALPN) > 0 {
		option.ALPN = append([]string{}, hints.ALPN...)
	}
	if !option.SkipCertVerify && hints.AllowInsecure != nil {
		option.SkipCertVerify = *hints.AllowInsecure
	}
	if option.Fingerprint == "" {
		option.Fingerprint = hints.Fingerprint
	}
	if option.RealityOpts.PublicKey == "" {
		option.RealityOpts.PublicKey = hints.RealityPublicKey
	}
	if option.RealityOpts.ShortID == "" {
		option.RealityOpts.ShortID = hints.RealityShortID
	}
	if option.ClientFingerprint == "" && option.RealityOpts.PublicKey != "" {
		option.ClientFingerprint = "chrome"
	}
}

func applyXHTTPHintsToTrojan(option *TrojanOption, hints xhttpHints) {
	if option == nil || !hints.hasAny() {
		return
	}

	if option.SNI == "" {
		option.SNI = firstNonEmptyString(hints.ServerName, hints.Host)
	}
	if len(option.ALPN) == 0 && len(hints.ALPN) > 0 {
		option.ALPN = append([]string{}, hints.ALPN...)
	}
	if !option.SkipCertVerify && hints.AllowInsecure != nil {
		option.SkipCertVerify = *hints.AllowInsecure
	}
	if option.Fingerprint == "" {
		option.Fingerprint = hints.Fingerprint
	}
	if option.RealityOpts.PublicKey == "" {
		option.RealityOpts.PublicKey = hints.RealityPublicKey
	}
	if option.RealityOpts.ShortID == "" {
		option.RealityOpts.ShortID = hints.RealityShortID
	}
	if option.ClientFingerprint == "" && option.RealityOpts.PublicKey != "" {
		option.ClientFingerprint = "chrome"
	}
}

var rateStringRegexp = regexp.MustCompile(`^(\d+)\s*([KMGT]?)([Bb])ps$`)

func StringToBps(s string) uint64 {
	if s == "" {
		return 0
	}

	// when have not unit, use Mbps
	if v, err := strconv.Atoi(s); err == nil {
		return StringToBps(fmt.Sprintf("%d Mbps", v))
	}

	m := rateStringRegexp.FindStringSubmatch(s)
	if m == nil {
		return 0
	}
	var n uint64 = 1
	switch m[2] {
	case "T":
		n *= 1000
		fallthrough
	case "G":
		n *= 1000
		fallthrough
	case "M":
		n *= 1000
		fallthrough
	case "K":
		n *= 1000
	}
	v, _ := strconv.ParseUint(m[1], 10, 64)
	n *= v
	if m[3] == "b" {
		// Bits, need to convert to bytes
		n /= 8
	}
	return n
}
