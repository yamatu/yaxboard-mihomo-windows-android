import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeRuntimeEchOptions keeps static subscription config only', () {
    final normalized = normalizeRuntimeEchOptions({
      'enable': true,
      'config': 'ZmFrZV9lY2hfY29uZmln',
      'config-list': 'https://dns.alidns.com/dns-query',
      'force-query': 'full',
      'query-server-name': 'cloudflare-ech.com',
    });

    expect(normalized, {
      'enable': true,
      'config': 'ZmFrZV9lY2hfY29uZmln',
    });
  });

  test('normalizeRuntimeEchOptions supports xboard query-server-only ech', () {
    final normalized = normalizeRuntimeEchOptions({
      'enable': true,
      'query-server-name': 'cloudflare-ech.com',
    });

    expect(normalized, {
      'enable': true,
      'config-list': 'https://dns.alidns.com/dns-query',
      'force-query': 'full',
      'query-server-name': 'cloudflare-ech.com',
    });
  });

  test('normalizeRuntimeEchOptions drops enable-only ech to avoid global query',
      () {
    final normalized = normalizeRuntimeEchOptions(
      {
        'enable': true,
      },
      fallbackConfigList: '',
      fallbackQueryServerName: '',
      fallbackForceQuery: '',
    );

    expect(normalized, isNull);
  });

  test('normalizeRuntimeEchOptions supports combined DNS ECH value', () {
    final normalized = normalizeRuntimeEchOptions({
      'enable': true,
      'config-list': 'cloudflare-ech.com+https://dns.alidns.com/dns-query',
    });

    expect(normalized, {
      'enable': true,
      'config-list': 'https://dns.alidns.com/dns-query',
      'force-query': 'full',
      'query-server-name': 'cloudflare-ech.com',
    });
  });

  test('normalizeRuntimeEchOptions uses client fallback DNS settings', () {
    final normalized = normalizeRuntimeEchOptions(
      {
        'enable': true,
        'config-list': 'https://example.test/dns-query',
      },
      fallbackQueryServerName: 'cloudflare-ech.com',
      fallbackForceQuery: 'full',
    );

    expect(normalized, {
      'enable': true,
      'config-list': 'https://example.test/dns-query',
      'force-query': 'full',
      'query-server-name': 'cloudflare-ech.com',
    });
  });
}
