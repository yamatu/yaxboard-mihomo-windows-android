package convert

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

type vShareExtra struct {
	host             string
	path             string
	mode             string
	headers          map[string]string
	downloadNetwork  string
	downloadSecurity string
	downloadAddress  string
	serverName       string
	alpn             []string
	allowInsecure    *bool
	echEnabled       bool
	echConfig        string
	echForceQuery    string
	echQueryServer   string
	realityPublicKey string
	realityShortID   string
	fingerprint      string
}

func handleVShareLink(names map[string]int, url *url.URL, scheme string, proxy map[string]any) error {
	// Xray VMessAEAD / VLESS share link standard
	// https://github.com/XTLS/Xray-core/discussions/716
	query := url.Query()
	extra := parseVShareExtra(query.Get("extra"))

	proxy["name"] = uniqueName(names, url.Fragment)
	if url.Hostname() == "" {
		return errors.New("url.Hostname() is empty")
	}
	if url.Port() == "" {
		return errors.New("url.Port() is empty")
	}

	proxy["type"] = scheme
	proxy["server"] = url.Hostname()
	proxy["port"] = url.Port()
	proxy["uuid"] = url.User.Username()
	proxy["udp"] = true

	security := strings.ToLower(query.Get("security"))
	if security == "" {
		security = strings.ToLower(extra.downloadSecurity)
	}

	if strings.HasSuffix(security, "tls") || security == "reality" {
		proxy["tls"] = true

		fingerprint := firstNonEmpty(query.Get("fp"), extra.fingerprint)
		if fingerprint == "" {
			proxy["client-fingerprint"] = "chrome"
		} else {
			proxy["client-fingerprint"] = fingerprint
		}

		if alpn := query.Get("alpn"); alpn != "" {
			proxy["alpn"] = strings.Split(alpn, ",")
		} else if len(extra.alpn) > 0 {
			proxy["alpn"] = extra.alpn
		}

		if allowInsecureRaw := query.Get("allowInsecure"); allowInsecureRaw != "" {
			if allowInsecure, err := strconv.ParseBool(allowInsecureRaw); err == nil {
				proxy["skip-cert-verify"] = allowInsecure
			}
		} else if extra.allowInsecure != nil {
			proxy["skip-cert-verify"] = *extra.allowInsecure
		}
	}

	if strings.HasSuffix(security, "tls") {
		applyVShareECHOptions(proxy, query, extra)
	}

	if sni := firstNonEmpty(query.Get("sni"), extra.serverName); sni != "" {
		proxy["servername"] = sni
	}

	realityPublicKey := firstNonEmpty(query.Get("pbk"), extra.realityPublicKey)
	if realityPublicKey != "" {
		proxy["reality-opts"] = map[string]any{
			"public-key": realityPublicKey,
			"short-id":   firstNonEmpty(query.Get("sid"), extra.realityShortID),
		}
	}

	switch query.Get("packetEncoding") {
	case "none":
	case "packet":
		proxy["packet-addr"] = true
	default:
		proxy["xudp"] = true
	}

	host := firstNonEmpty(query.Get("host"), extra.host, extra.downloadAddress)
	path := firstNonEmpty(query.Get("path"), extra.path)
	mode := firstNonEmpty(query.Get("mode"), extra.mode)

	network := strings.ToLower(query.Get("type"))
	if network == "" {
		network = strings.ToLower(extra.downloadNetwork)
	}
	if network == "" {
		network = "tcp"
	}

	fakeType := strings.ToLower(query.Get("headerType"))
	if fakeType == "http" {
		network = "http"
	} else if network == "http" {
		network = "h2"
	}

	useXHTTP := network == "xhttp" || network == "splithttp" || network == "split-http"
	useHTTPUpgrade := network == "httpupgrade" || network == "http-upgrade"
	if useXHTTP {
		network = "xhttp"
	} else if useHTTPUpgrade {
		network = "ws"
	}

	proxy["network"] = network

	switch network {
	case "tcp":
		if fakeType != "none" {
			headers := make(map[string]any)
			httpOpts := make(map[string]any)
			httpOpts["path"] = []string{"/"}

			if host != "" {
				headers["Host"] = []string{host}
			}

			if method := query.Get("method"); method != "" {
				httpOpts["method"] = method
			}

			if path != "" {
				httpOpts["path"] = []string{path}
			}

			httpOpts["headers"] = headers
			proxy["http-opts"] = httpOpts
		}

	case "http":
		headers := make(map[string]any)
		h2Opts := make(map[string]any)
		h2Opts["path"] = []string{"/"}

		if path != "" {
			h2Opts["path"] = []string{path}
		}
		if host != "" {
			h2Opts["host"] = []string{host}
		}

		h2Opts["headers"] = headers
		proxy["h2-opts"] = h2Opts

	case "ws":
		headers := make(map[string]any)
		wsOpts := make(map[string]any)

		headers["User-Agent"] = RandUserAgent()
		if host != "" {
			headers["Host"] = host
		}
		for key, value := range extra.headers {
			if _, exists := headers[key]; !exists && value != "" {
				headers[key] = value
			}
		}

		if path == "" {
			path = "/"
		}
		wsOpts["path"] = path
		wsOpts["headers"] = headers

		if useHTTPUpgrade {
			wsOpts["v2ray-http-upgrade"] = true
		}
		if strings.EqualFold(mode, "packet-up") {
			wsOpts["v2ray-http-upgrade-fast-open"] = true
		}

		if earlyData := query.Get("ed"); earlyData != "" {
			med, err := strconv.Atoi(earlyData)
			if err != nil {
				return fmt.Errorf("bad WebSocket max early data size: %v", err)
			}
			if useHTTPUpgrade {
				wsOpts["v2ray-http-upgrade-fast-open"] = true
			} else {
				wsOpts["max-early-data"] = med
				wsOpts["early-data-header-name"] = "Sec-WebSocket-Protocol"
			}
		}
		if earlyDataHeader := query.Get("eh"); earlyDataHeader != "" {
			wsOpts["early-data-header-name"] = earlyDataHeader
		}

		proxy["ws-opts"] = wsOpts

	case "xhttp":
		xhttpOpts := make(map[string]any)
		xhttpHeaders := make(map[string]any)

		if host != "" {
			xhttpOpts["host"] = host
			xhttpHeaders["Host"] = host
		}
		for key, value := range extra.headers {
			if value != "" {
				xhttpHeaders[key] = value
			}
		}

		if path == "" {
			path = "/"
		}
		xhttpOpts["path"] = path
		if mode != "" {
			xhttpOpts["mode"] = mode
		}
		if len(xhttpHeaders) > 0 {
			xhttpOpts["headers"] = xhttpHeaders
		}
		if extraMap := decodeVShareExtraMap(query.Get("extra")); len(extraMap) > 0 {
			xhttpOpts["extra"] = extraMap
		}

		proxy["xhttp-opts"] = xhttpOpts

	case "grpc":
		grpcOpts := make(map[string]any)
		grpcOpts["grpc-service-name"] = query.Get("serviceName")
		proxy["grpc-opts"] = grpcOpts
	}

	return nil
}

func applyVShareECHOptions(proxy map[string]any, query url.Values, extra vShareExtra) {
	echQueryValue := query.Get("ech")
	echQueryServerFromCombined, echConfigFromCombined := splitV2rayNECHValue(echQueryValue)
	echValue := firstNonEmpty(
		query.Get("echConfigList"),
		query.Get("ech_config_list"),
		query.Get("ech-config-list"),
		echConfigFromCombined,
		echQueryValue,
		extra.echConfig,
	)
	echForceQuery := firstNonEmpty(
		query.Get("echForceQuery"),
		query.Get("ech_force_query"),
		query.Get("ech-force-query"),
		extra.echForceQuery,
	)
	echQueryServer := firstNonEmpty(
		query.Get("echQueryServerName"),
		query.Get("ech_query_server_name"),
		query.Get("ech-query-server-name"),
		echQueryServerFromCombined,
		extra.echQueryServer,
	)
	echEnabled := query.Has("ech") ||
		query.Has("echConfigList") ||
		query.Has("ech_config_list") ||
		query.Has("ech-config-list") ||
		query.Has("echForceQuery") ||
		query.Has("ech_force_query") ||
		query.Has("ech-force-query") ||
		query.Has("echQueryServerName") ||
		query.Has("ech_query_server_name") ||
		query.Has("ech-query-server-name") ||
		extra.echEnabled
	if !echEnabled {
		return
	}
	if isECHDisabledValue(echValue) {
		return
	}

	echOpts := map[string]any{"enable": true}
	if config, ok := normalizeECHConfigForMihomo(echValue); ok {
		echOpts["config"] = config
	} else if looksLikeECHNameserver(echValue) {
		echOpts["config-list"] = echValue
	}
	if echForceQuery != "" {
		echOpts["force-query"] = echForceQuery
	}
	if echQueryServer != "" {
		echOpts["query-server-name"] = echQueryServer
	}
	proxy["ech-opts"] = echOpts
}

func parseVShareURL(raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err == nil {
		return u, nil
	}

	fixed := escapeRawExtraInShareLink(raw)
	if fixed == raw {
		return nil, err
	}

	return url.Parse(fixed)
}

func escapeRawExtraInShareLink(raw string) string {
	parts := strings.SplitN(raw, "#", 2)
	base := parts[0]
	fragment := ""
	if len(parts) == 2 {
		fragment = "#" + parts[1]
	}

	queryIndex := strings.IndexByte(base, '?')
	if queryIndex < 0 {
		return raw
	}

	pathPart := base[:queryIndex+1]
	queryPart := base[queryIndex+1:]
	extraIndex := strings.Index(queryPart, "extra=")
	if extraIndex < 0 {
		return raw
	}

	valueStart := extraIndex + len("extra=")
	extraValue := queryPart[valueStart:]
	if extraValue == "" || strings.HasPrefix(strings.ToLower(extraValue), "%7b") {
		return raw
	}

	if !strings.HasPrefix(extraValue, "{") {
		return raw
	}

	extraEnd := findJSONObjectEnd(extraValue)
	if extraEnd <= 0 {
		extraEnd = len(extraValue)
	}

	rawJSON := extraValue[:extraEnd]
	tail := extraValue[extraEnd:]
	escaped := url.QueryEscape(rawJSON)

	queryPart = queryPart[:valueStart] + escaped + tail
	return pathPart + queryPart + fragment
}

func findJSONObjectEnd(s string) int {
	depth := 0
	inString := false
	escaped := false

	for i, r := range s {
		if inString {
			if escaped {
				escaped = false
				continue
			}
			switch r {
			case '\\':
				escaped = true
			case '"':
				inString = false
			}
			continue
		}

		switch r {
		case '"':
			inString = true
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return i + 1
			}
		}
	}

	return -1
}

func decodeVShareExtraMap(raw string) map[string]any {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}

	if extraMap := decodeJSONMap(raw); extraMap != nil {
		return extraMap
	}

	if unescaped, err := url.QueryUnescape(raw); err == nil {
		return decodeJSONMap(unescaped)
	}

	return nil
}

func parseVShareExtra(raw string) vShareExtra {
	result := vShareExtra{headers: map[string]string{}}
	if raw == "" {
		return result
	}

	extraMap := decodeJSONMap(raw)
	if extraMap == nil {
		if unescaped, err := url.QueryUnescape(raw); err == nil {
			extraMap = decodeJSONMap(unescaped)
		}
	}
	if extraMap == nil {
		return result
	}

	result.host = valueToString(extraMap["host"])
	result.path = valueToString(extraMap["path"])
	result.mode = valueToString(extraMap["mode"])

	if headers := valueToStringMap(extraMap["headers"]); len(headers) > 0 {
		for key, value := range headers {
			result.headers[key] = value
		}
	}

	extraDetail := valueToMap(extraMap["extra"])
	if extraDetail == nil {
		return result
	}

	if headers := valueToStringMap(extraDetail["headers"]); len(headers) > 0 {
		for key, value := range headers {
			result.headers[key] = value
		}
	}

	downloadSettings := valueToMap(extraDetail["downloadSettings"])
	if downloadSettings == nil {
		return result
	}

	result.downloadAddress = valueToString(downloadSettings["address"])
	result.downloadNetwork = strings.ToLower(valueToString(downloadSettings["network"]))
	result.downloadSecurity = strings.ToLower(valueToString(downloadSettings["security"]))

	tlsSettings := valueToMap(downloadSettings["tlsSettings"])
	if tlsSettings != nil {
		result.serverName = valueToString(tlsSettings["serverName"])
		result.alpn = valueToStringSlice(tlsSettings["alpn"])
		if insecure, ok := valueToBool(tlsSettings["allowInsecure"]); ok {
			result.allowInsecure = &insecure
		}
		result.fingerprint = valueToString(tlsSettings["fingerprint"])
		parseXrayECHSettings(tlsSettings, &result)
	}

	xhttpSettings := valueToMap(downloadSettings["xhttpSettings"])
	if xhttpSettings != nil {
		if result.host == "" {
			result.host = valueToString(xhttpSettings["host"])
		}
		if result.path == "" {
			result.path = valueToString(xhttpSettings["path"])
		}
		if result.mode == "" {
			result.mode = valueToString(xhttpSettings["mode"])
		}
		if headers := valueToStringMap(xhttpSettings["headers"]); len(headers) > 0 {
			for key, value := range headers {
				if _, exists := result.headers[key]; !exists {
					result.headers[key] = value
				}
			}
		}
	}

	realitySettings := valueToMap(downloadSettings["realitySettings"])
	if realitySettings != nil {
		result.realityPublicKey = valueToString(realitySettings["publicKey"])
		result.realityShortID = valueToString(realitySettings["shortId"])
		if result.serverName == "" {
			result.serverName = valueToString(realitySettings["serverName"])
		}
		if result.fingerprint == "" {
			result.fingerprint = valueToString(realitySettings["fingerprint"])
		}
	}

	if result.path == "" {
		result.path = valueToString(downloadSettings["path"])
	}
	if result.mode == "" {
		result.mode = valueToString(downloadSettings["mode"])
	}

	return result
}

func parseXrayECHConfigList(value any) (bool, string) {
	for _, item := range valueToStringSlice(value) {
		_, configFromCombined := splitV2rayNECHValue(item)
		if configFromCombined != "" {
			item = configFromCombined
		}
		if config, ok := normalizeECHConfigForMihomo(item); ok {
			return true, config
		}
		if looksLikeECHNameserver(item) {
			return true, strings.TrimSpace(item)
		}
	}

	return len(valueToStringSlice(value)) > 0, ""
}

func parseXrayECHQueryServerName(value any) string {
	for _, item := range valueToStringSlice(value) {
		queryServerName, _ := splitV2rayNECHValue(item)
		if queryServerName != "" {
			return queryServerName
		}
	}
	return ""
}

func splitV2rayNECHValue(value string) (string, string) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", ""
	}
	if !strings.Contains(value, "+") {
		fields := strings.Fields(value)
		if len(fields) == 2 && strings.TrimSpace(fields[0]) != "" && looksLikeECHNameserver(fields[1]) {
			return strings.TrimSpace(fields[0]), strings.TrimSpace(fields[1])
		}
		return "", ""
	}

	parts := strings.SplitN(value, "+", 2)
	if len(parts) != 2 {
		return "", ""
	}

	queryServerName := strings.TrimSpace(parts[0])
	configList := strings.TrimSpace(parts[1])
	if queryServerName == "" || !looksLikeECHNameserver(configList) {
		return "", ""
	}
	return queryServerName, configList
}

func parseXrayECHSettings(tlsSettings map[string]any, result *vShareExtra) {
	if tlsSettings == nil || result == nil {
		return
	}

	echEnabled, echConfig := parseXrayECHConfigList(firstNonNil(
		tlsSettings["echConfigList"],
		tlsSettings["ech_config_list"],
		tlsSettings["ech-config-list"],
	))
	result.echEnabled = echEnabled
	result.echConfig = echConfig
	result.echForceQuery = firstNonEmpty(
		valueToString(tlsSettings["echForceQuery"]),
		valueToString(tlsSettings["ech_force_query"]),
		valueToString(tlsSettings["ech-force-query"]),
	)
	result.echQueryServer = firstNonEmpty(
		valueToString(tlsSettings["echQueryServerName"]),
		valueToString(tlsSettings["ech_query_server_name"]),
		valueToString(tlsSettings["ech-query-server-name"]),
		valueToString(tlsSettings["queryServerName"]),
		valueToString(tlsSettings["query_server_name"]),
		valueToString(tlsSettings["query-server-name"]),
		parseXrayECHQueryServerName(firstNonNil(
			tlsSettings["echConfigList"],
			tlsSettings["ech_config_list"],
			tlsSettings["ech-config-list"],
		)),
	)

	echSettings := valueToMap(tlsSettings["ech"])
	if echSettings == nil {
		return
	}
	if enabled, ok := valueToBool(echSettings["enabled"]); ok {
		result.echEnabled = enabled
	}
	nestedEnabled, nestedConfig := parseXrayECHConfigList(firstNonNil(
		echSettings["config"],
		echSettings["configList"],
		echSettings["config_list"],
		echSettings["config-list"],
		echSettings["echConfigList"],
		echSettings["ech_config_list"],
		echSettings["ech-config-list"],
	))
	if nestedEnabled {
		result.echEnabled = true
		result.echConfig = nestedConfig
	}
	result.echForceQuery = firstNonEmpty(
		valueToString(echSettings["forceQuery"]),
		valueToString(echSettings["force_query"]),
		valueToString(echSettings["force-query"]),
		result.echForceQuery,
	)
	result.echQueryServer = firstNonEmpty(
		valueToString(echSettings["queryServerName"]),
		valueToString(echSettings["query_server_name"]),
		valueToString(echSettings["query-server-name"]),
		parseXrayECHQueryServerName(firstNonNil(
			echSettings["config"],
			echSettings["configList"],
			echSettings["config_list"],
			echSettings["config-list"],
			echSettings["echConfigList"],
			echSettings["ech_config_list"],
			echSettings["ech-config-list"],
		)),
		result.echQueryServer,
	)
}

func normalizeECHConfigForMihomo(value string) (string, bool) {
	value = strings.ReplaceAll(strings.TrimSpace(value), " ", "+")
	if value == "" || isECHDisabledValue(value) {
		return "", false
	}

	decoders := []*base64.Encoding{
		base64.StdEncoding,
		base64.RawStdEncoding,
		base64.URLEncoding,
		base64.RawURLEncoding,
	}
	for _, decoder := range decoders {
		if decoded, err := decoder.DecodeString(value); err == nil && len(decoded) > 0 {
			return base64.StdEncoding.EncodeToString(decoded), true
		}
	}

	return "", false
}

func isECHDisabledValue(value string) bool {
	value = strings.TrimSpace(value)
	return strings.EqualFold(value, "false") ||
		strings.EqualFold(value, "none") ||
		value == "0"
}

func looksLikeECHNameserver(value string) bool {
	value = strings.TrimSpace(value)
	return strings.HasPrefix(value, "https://") ||
		strings.HasPrefix(value, "tls://") ||
		strings.HasPrefix(value, "quic://") ||
		strings.HasPrefix(value, "dhcp://") ||
		strings.HasPrefix(value, "system://")
}

func firstNonNil(values ...any) any {
	for _, value := range values {
		if value != nil {
			return value
		}
	}
	return nil
}

func parseVShareExtraAny(v any) vShareExtra {
	switch value := v.(type) {
	case nil:
		return vShareExtra{headers: map[string]string{}}
	case string:
		return parseVShareExtra(value)
	case map[string]any:
		if raw, err := json.Marshal(value); err == nil {
			return parseVShareExtra(string(raw))
		}
	}
	return parseVShareExtra(valueToString(v))
}

func decodeJSONMap(raw string) map[string]any {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}

	var result map[string]any
	if err := json.Unmarshal([]byte(raw), &result); err == nil {
		return result
	}

	if unquoted, err := strconv.Unquote(raw); err == nil {
		if err := json.Unmarshal([]byte(unquoted), &result); err == nil {
			return result
		}
	}

	return nil
}

func valueToMap(v any) map[string]any {
	if v == nil {
		return nil
	}
	if m, ok := v.(map[string]any); ok {
		return m
	}
	return nil
}

func valueToString(v any) string {
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
	case []any:
		for _, item := range value {
			if s := valueToString(item); s != "" {
				return s
			}
		}
	default:
		s := strings.TrimSpace(fmt.Sprint(value))
		if !strings.EqualFold(s, "<nil>") {
			return s
		}
	}
	return ""
}

func valueToStringSlice(v any) []string {
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
			if s := valueToString(item); s != "" {
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

func valueToStringMap(v any) map[string]string {
	m, ok := v.(map[string]any)
	if !ok {
		return nil
	}

	result := make(map[string]string, len(m))
	for key, value := range m {
		if strings.TrimSpace(key) == "" {
			continue
		}
		if s := valueToString(value); s != "" {
			result[key] = s
		}
	}
	return result
}

func valueToBool(v any) (bool, bool) {
	switch value := v.(type) {
	case bool:
		return value, true
	case string:
		if value == "" {
			return false, false
		}
		parsed, err := strconv.ParseBool(value)
		if err != nil {
			return false, false
		}
		return parsed, true
	case float64:
		return value != 0, true
	case int:
		return value != 0, true
	case int64:
		return value != 0, true
	}
	return false, false
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if s := strings.TrimSpace(value); s != "" {
			return s
		}
	}
	return ""
}
