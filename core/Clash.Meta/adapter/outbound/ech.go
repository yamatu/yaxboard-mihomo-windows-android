package outbound

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/metacubex/mihomo/component/ech"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/dns"
)

type ECHOptions struct {
	Enable          bool   `proxy:"enable,omitempty" obfs:"enable,omitempty"`
	Config          string `proxy:"config,omitempty" obfs:"config,omitempty"`
	ConfigList      string `proxy:"config-list,omitempty" obfs:"config-list,omitempty"`
	ForceQuery      string `proxy:"force-query,omitempty" obfs:"force-query,omitempty"`
	QueryServerName string `proxy:"query-server-name,omitempty" obfs:"query-server-name,omitempty"`
}

func (o ECHOptions) Parse() (*ech.Config, error) {
	if !o.Enable {
		return nil, nil
	}
	if queryServerName, configList := splitECHConfigListValue(o.ConfigList); configList != "" {
		o.ConfigList = configList
		if strings.TrimSpace(o.QueryServerName) == "" {
			o.QueryServerName = queryServerName
		}
	}
	echConfig := &ech.Config{}
	list, hasStaticConfig, err := o.parseStaticConfig()
	if err != nil {
		return nil, err
	}

	forceQuery := strings.EqualFold(strings.TrimSpace(o.ForceQuery), "full")
	if hasStaticConfig && !forceQuery {
		echConfig.GetEncryptedClientHelloConfigList = func(ctx context.Context, serverName string) ([]byte, error) {
			return list, nil
		}
		return echConfig, nil
	}

	echResolver, err := o.resolver()
	if err != nil {
		return nil, err
	}
	queryServerName := strings.TrimSpace(o.QueryServerName)
	if queryServerName == "" {
		queryServerName = strings.TrimSpace(o.ConfigList)
	}
	if strings.Contains(queryServerName, "://") {
		queryServerName = ""
	}

	echConfig.GetEncryptedClientHelloConfigList = func(ctx context.Context, serverName string) ([]byte, error) {
		if !forceQuery && hasStaticConfig {
			return list, nil
		}
		queryName := serverName
		if queryServerName != "" {
			queryName = queryServerName
		}
		return resolver.ResolveECHWithResolver(ctx, queryName, echResolver)
	}
	return echConfig, nil
}

func (o ECHOptions) parseStaticConfig() ([]byte, bool, error) {
	config := strings.TrimSpace(o.Config)
	if config == "" {
		config = strings.TrimSpace(o.ConfigList)
	}
	if config == "" || strings.Contains(config, "://") {
		return nil, false, nil
	}
	list, err := base64.StdEncoding.DecodeString(config)
	if err != nil {
		return nil, false, fmt.Errorf("base64 decode ech config string failed: %v", err)
	}
	return list, true, nil
}

func (o ECHOptions) resolver() (resolver.Resolver, error) {
	configList := strings.TrimSpace(o.ConfigList)
	if configList == "" || !strings.Contains(configList, "://") {
		return resolver.ProxyServerHostResolver, nil
	}

	if dns.ParseNameServer == nil {
		return resolver.ProxyServerHostResolver, nil
	}

	nameservers, err := dns.ParseNameServer([]string{configList})
	if err != nil {
		return nil, fmt.Errorf("parse ech config-list nameserver failed: %w", err)
	}
	defaultNameservers, err := dns.ParseNameServer([]string{"223.5.5.5", "119.29.29.29"})
	if err != nil {
		return nil, fmt.Errorf("parse ech default nameserver failed: %w", err)
	}
	resolvers := dns.NewResolver(dns.Config{
		Main:    nameservers,
		Default: defaultNameservers,
	})
	if resolvers.Resolver == nil {
		return nil, fmt.Errorf("create ech config-list resolver failed")
	}
	return resolvers.Resolver, nil
}

func splitECHConfigListValue(value string) (queryServerName, configList string) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", ""
	}
	if !strings.Contains(value, "+") {
		fields := strings.Fields(value)
		if len(fields) == 2 && strings.Contains(fields[1], "://") {
			return strings.TrimSpace(fields[0]), strings.TrimSpace(fields[1])
		}
		return "", ""
	}
	parts := strings.SplitN(value, "+", 2)
	if len(parts) != 2 {
		return "", ""
	}
	queryServerName = strings.TrimSpace(parts[0])
	configList = strings.TrimSpace(parts[1])
	if queryServerName == "" || !strings.Contains(configList, "://") {
		return "", ""
	}
	return queryServerName, configList
}
