import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../common/path.dart';
import '../../core/core.dart';
import '../../infrastructure/network/direct_domain_matcher.dart';
import '../core/config_settings.dart';

final _logger = FileLogger('config_file_loader.dart');

List<String> _cachedForceDirectDomains = const [];
const String _defaultDohResolverUrl = 'https://dns.alidns.com/resolve';
String _cachedDohResolverUrl = _defaultDohResolverUrl;
bool _cachedEnableDohResolver = true;

class ConfigFileLoader {
  static const String configPath = 'assets/config/xboard.config.yaml';
  static const String externalConfigFileName = 'xboard.config.yaml';
  static const String externalCacheFileName = 'xboard.remote.cached.yaml';
  static const String bootstrapRemoteEnvKey = 'XBOARD_BOOTSTRAP_URL';

  static Future<ConfigSettings> loadFromFile() async {
    try {
      final yamlString = await _loadBestYamlString();
      final config = _parseYamlString(yamlString);
      _logger.info(
        'Loaded bootstrap config, provider: ${config.currentProvider}',
      );
      return config;
    } catch (e, stackTrace) {
      _logger.error('Failed to load bootstrap config', e, stackTrace);
      return const ConfigSettings();
    }
  }

  static Future<Map<String, dynamic>> loadExtendedConfig() async {
    try {
      final yamlString = await _loadBestYamlString();
      final yamlDoc = loadYaml(yamlString);
      final configMap = _yamlToMap(yamlDoc) as Map<String, dynamic>;
      return configMap['xboard'] as Map<String, dynamic>? ?? {};
    } catch (e, stackTrace) {
      _logger.error('Failed to load extended bootstrap config', e, stackTrace);
      return {};
    }
  }

  static Future<String> _loadBestYamlString() async {
    final assetYaml = await _loadAssetYaml();

    final remoteYaml = await _loadBootstrapRemoteYaml(assetYaml);
    if (remoteYaml != null) {
      return remoteYaml;
    }

    final externalYaml = await _loadExternalYaml();
    if (externalYaml != null) {
      _logger.info('Loaded bootstrap config from external file');
      return externalYaml;
    }

    _logger.info('Loaded bootstrap config from bundled asset');
    return assetYaml;
  }

  static Future<String> _loadAssetYaml() async {
    return await rootBundle.loadString(configPath);
  }

  static Future<String?> _loadExternalYaml() async {
    try {
      final file = File(await getExternalConfigFilePath());
      if (!await file.exists()) {
        return null;
      }
      final content = await file.readAsString();
      return content.trim().isEmpty ? null : content;
    } catch (e, stackTrace) {
      _logger.warning(
          'Failed to read external bootstrap config', e, stackTrace);
      return null;
    }
  }

  static Future<String?> _loadBootstrapRemoteYaml(String assetYaml) async {
    try {
      final assetConfig = _parseYamlString(assetYaml);
      final remoteUrl = _resolveBootstrapRemoteUrl(assetConfig);
      if (remoteUrl == null || remoteUrl.isEmpty) {
        return await _loadCachedRemoteYaml();
      }

      final bootstrapConfig = assetConfig.bootstrapConfig;
      final yaml = await _downloadYaml(
        remoteUrl,
        headers: bootstrapConfig.headers,
        timeout: bootstrapConfig.timeout,
      );

      if (yaml == null || yaml.trim().isEmpty) {
        return await _loadCachedRemoteYaml();
      }

      if (bootstrapConfig.cacheRemoteToDisk) {
        await _writeRemoteCache(yaml);
      }
      _logger.info('Loaded bootstrap config from remote URL: $remoteUrl');
      return yaml;
    } catch (e, stackTrace) {
      _logger.warning('Failed to load remote bootstrap config', e, stackTrace);
      return await _loadCachedRemoteYaml();
    }
  }

  static String? _resolveBootstrapRemoteUrl(ConfigSettings assetConfig) {
    final envUrl = const String.fromEnvironment(bootstrapRemoteEnvKey);
    if (envUrl.trim().isNotEmpty) {
      return envUrl.trim();
    }

    final bootstrapUrl = assetConfig.bootstrapConfig.remoteUrl;
    if (bootstrapUrl != null && bootstrapUrl.trim().isNotEmpty) {
      return bootstrapUrl.trim();
    }

    return null;
  }

  static Future<String?> _loadCachedRemoteYaml() async {
    try {
      final file = File(await getRemoteCacheFilePath());
      if (!await file.exists()) {
        return null;
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return null;
      }
      _logger.info('Loaded bootstrap config from cached remote file');
      return content;
    } catch (e, stackTrace) {
      _logger.warning(
          'Failed to read cached remote bootstrap config', e, stackTrace);
      return null;
    }
  }

  static Future<void> _writeRemoteCache(String yaml) async {
    try {
      final file = File(await getRemoteCacheFilePath());
      await file.parent.create(recursive: true);
      await file.writeAsString(yaml, flush: true);
    } catch (e, stackTrace) {
      _logger.warning('Failed to cache remote bootstrap config', e, stackTrace);
    }
  }

  static Future<String?> _downloadYaml(
    String url, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        sendTimeout: timeout,
        receiveTimeout: timeout,
        responseType: ResponseType.plain,
        headers: headers,
      ),
    );

    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        if (kDebugMode) {
          client.badCertificateCallback = (_, __, ___) => true;
        }
        return client;
      };
    }

    try {
      final response = await dio.get<String>(url);
      if (response.statusCode != 200) {
        _logger.warning(
          'Bootstrap remote config request failed: ${response.statusCode}',
        );
        return null;
      }
      return response.data;
    } catch (e, stackTrace) {
      _logger.warning('Bootstrap remote config download failed', e, stackTrace);
      return null;
    } finally {
      dio.close(force: true);
    }
  }

  static ConfigSettings _parseYamlString(String yamlString) {
    final yamlDoc = loadYaml(yamlString);
    final configMap = _yamlToMap(yamlDoc) as Map<String, dynamic>;
    final xboardConfig = configMap['xboard'] as Map<String, dynamic>? ?? {};

    final provider = xboardConfig['provider'] as String? ?? 'Flclash';
    final bootstrapConfigJson =
        xboardConfig['bootstrap'] as Map<String, dynamic>? ?? {};
    final remoteConfigJson =
        xboardConfig['remote_config'] as Map<String, dynamic>? ?? {};
    final subscriptionJson =
        xboardConfig['subscription'] as Map<String, dynamic>? ?? {};
    final logJson = xboardConfig['log'] as Map<String, dynamic>? ?? {};

    return ConfigSettings(
      currentProvider: provider,
      bootstrapConfig: _parseBootstrapConfig(bootstrapConfigJson),
      remoteConfig: _parseRemoteConfig(remoteConfigJson),
      subscription: _parseSubscriptionSettings(subscriptionJson),
      log: _parseLogSettings(logJson),
    );
  }

  static BootstrapConfigSettings _parseBootstrapConfig(
    Map<String, dynamic> json,
  ) {
    final remoteUrl =
        json['remote_url'] as String? ?? json['remoteUrl'] as String?;
    final headers = (json['headers'] as Map<String, dynamic>?)
            ?.map((key, value) => MapEntry(key, value.toString())) ??
        const <String, String>{};
    final timeoutSeconds =
        json['timeout_seconds'] as int? ?? json['timeoutSeconds'] as int? ?? 15;
    final cacheRemoteToDisk = json['cache_remote_to_disk'] as bool? ??
        json['cacheRemoteToDisk'] as bool? ??
        true;

    return BootstrapConfigSettings(
      remoteUrl: remoteUrl,
      headers: headers,
      timeout: Duration(seconds: timeoutSeconds),
      cacheRemoteToDisk: cacheRemoteToDisk,
    );
  }

  static dynamic _yamlToMap(dynamic yaml) {
    if (yaml is YamlMap) {
      final map = <String, dynamic>{};
      yaml.forEach((key, value) {
        map[key.toString()] = _yamlToMap(value);
      });
      return map;
    }
    if (yaml is YamlList) {
      return yaml.map((item) => _yamlToMap(item)).toList();
    }
    return yaml;
  }

  static RemoteConfigSettings _parseRemoteConfig(Map<String, dynamic> json) {
    final sourcesList = json['sources'] as List<dynamic>? ?? [];
    final sources = sourcesList
        .whereType<Map<String, dynamic>>()
        .map(_parseRemoteSource)
        .toList();

    return RemoteConfigSettings(
      sources: sources,
      maxRetries: json['max_retries'] as int? ?? 3,
      timeout: Duration(seconds: json['timeout_seconds'] as int? ?? 10),
      retryDelay: Duration(seconds: json['retry_delay_seconds'] as int? ?? 2),
    );
  }

  static RemoteSourceConfig _parseRemoteSource(Map<String, dynamic> json) {
    final headers = (json['headers'] as Map<String, dynamic>?)
        ?.map((key, value) => MapEntry(key, value.toString()));
    return RemoteSourceConfig(
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      headers: headers,
      timeout: json['timeout_seconds'] != null
          ? Duration(seconds: json['timeout_seconds'] as int)
          : null,
      encryptionKey:
          json['encryption_key'] as String? ?? json['encryptionKey'] as String?,
    );
  }

  static SubscriptionSettings _parseSubscriptionSettings(
    Map<String, dynamic> json,
  ) {
    return SubscriptionSettings(
      preferEncrypt: json['prefer_encrypt'] as bool? ?? false,
    );
  }

  static LogSettings _parseLogSettings(Map<String, dynamic> json) {
    return LogSettings(
      enabled: json['enabled'] as bool? ?? true,
      level: json['level'] as String? ?? 'info',
      prefix: json['prefix'] as String? ?? '[XBoard]',
    );
  }

  static Future<String> getExternalConfigFilePath() async {
    final homeDir = await appPath.homeDirPath;
    return p.join(homeDir, externalConfigFileName);
  }

  static Future<String> getRemoteCacheFilePath() async {
    final homeDir = await appPath.homeDirPath;
    return p.join(homeDir, externalCacheFileName);
  }
}

extension ConfigFileLoaderHelper on ConfigFileLoader {
  static Future<SubscriptionSettings> getSubscriptionSettings() async {
    try {
      final config = await ConfigFileLoader.loadExtendedConfig();
      final subscriptionJson =
          config['subscription'] as Map<String, dynamic>? ?? {};
      return SubscriptionSettings(
        preferEncrypt: subscriptionJson['prefer_encrypt'] as bool? ?? false,
      );
    } catch (_) {
      return const SubscriptionSettings();
    }
  }

  static Future<bool> getPreferEncrypt() async {
    try {
      final settings = await getSubscriptionSettings();
      return settings.preferEncrypt;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> getEnableRace() async {
    try {
      final settings = await getSubscriptionSettings();
      return settings.enableRace;
    } catch (_) {
      return true;
    }
  }

  static Future<String> getLatencyTestUrl() async {
    try {
      final config = await ConfigFileLoader.loadExtendedConfig();
      final latencyTest = config['latency_test'] as Map<String, dynamic>? ?? {};
      return latencyTest['test_url'] as String? ??
          'http://www.gstatic.com/generate_204';
    } catch (_) {
      return 'http://www.gstatic.com/generate_204';
    }
  }

  static Future<Map<String, dynamic>> getSdkConfig() async {
    try {
      final config = await ConfigFileLoader.loadExtendedConfig();
      return config['sdk'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> getAppConfig() async {
    try {
      final config = await ConfigFileLoader.loadExtendedConfig();
      return config['app'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> getSecurityConfig() async {
    try {
      final config = await ConfigFileLoader.loadExtendedConfig();
      return config['security'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> getNetworkConfig() async {
    try {
      final config = await ConfigFileLoader.loadExtendedConfig();
      return config['network'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<String> getDecryptKey() async {
    try {
      final config = await ConfigFileLoader.loadExtendedConfig();
      final subscription =
          config['subscription'] as Map<String, dynamic>? ?? {};
      return subscription['decrypt_key'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<Map<String, String>> getUserAgents() async {
    try {
      final security = await getSecurityConfig();
      final userAgents = security['user_agents'] as Map<String, dynamic>? ?? {};
      return userAgents.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> getCertificateConfig() async {
    return {
      'path': 'assets/cer/client-cert.crt',
      'enabled': false,
    };
  }

  static Future<String> getAppTitle() async {
    try {
      final app = await getAppConfig();
      return app['title'] as String? ?? 'XBoard';
    } catch (_) {
      return 'XBoard';
    }
  }

  static Future<String> getAppWebsite() async {
    try {
      final app = await getAppConfig();
      return app['website'] as String? ?? 'example.com';
    } catch (_) {
      return 'example.com';
    }
  }

  static Future<String?> getObfuscationPrefix() async {
    try {
      final security = await getSecurityConfig();
      final prefix = security['obfuscation_prefix'];
      if (prefix == null || (prefix is String && prefix.isEmpty)) {
        return null;
      }
      return prefix as String;
    } catch (e, stackTrace) {
      _logger.warning('Failed to get obfuscation prefix', e, stackTrace);
      return null;
    }
  }

  static Future<List<String>> getForceDirectDomains() async {
    try {
      final config = await ConfigFileLoader.loadExtendedConfig();
      final network = config['network'] as Map<String, dynamic>? ?? {};
      final raw = network['force_direct_domains'];

      if (raw == null) {
        _cachedForceDirectDomains = const [];
        return const [];
      }

      if (raw is List) {
        final domains = raw
            .whereType<Object>()
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList();
        final normalized = DirectDomainMatcher.normalizeDomainList(domains);
        _cachedForceDirectDomains = normalized;
        return normalized;
      }

      if (raw is String) {
        final domains = raw
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final normalized = DirectDomainMatcher.normalizeDomainList(domains);
        _cachedForceDirectDomains = normalized;
        return normalized;
      }

      _cachedForceDirectDomains = const [];
      return const [];
    } catch (e, stackTrace) {
      _logger.warning('Failed to get force direct domains', e, stackTrace);
      _cachedForceDirectDomains = const [];
      return const [];
    }
  }

  static List<String> getCachedForceDirectDomains() {
    return List<String>.from(_cachedForceDirectDomains);
  }

  static Future<String> getDohResolverUrl() async {
    try {
      final network = await getNetworkConfig();
      final raw = network['doh_url'];

      if (raw is String && raw.trim().isNotEmpty) {
        final candidate = raw.trim();
        final uri = Uri.tryParse(candidate);
        if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
          _cachedDohResolverUrl = candidate;
          return candidate;
        }
      }

      _cachedDohResolverUrl = _defaultDohResolverUrl;
      return _defaultDohResolverUrl;
    } catch (e, stackTrace) {
      _logger.warning('Failed to get DoH resolver URL', e, stackTrace);
      _cachedDohResolverUrl = _defaultDohResolverUrl;
      return _defaultDohResolverUrl;
    }
  }

  static String getCachedDohResolverUrl() {
    return _cachedDohResolverUrl;
  }

  static Future<bool> getEnableDohResolver() async {
    try {
      final network = await getNetworkConfig();
      final raw = network['enable_doh_resolver'];

      if (raw is bool) {
        _cachedEnableDohResolver = raw;
        return raw;
      }

      if (raw is String) {
        final normalized = raw.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
          _cachedEnableDohResolver = true;
          return true;
        }
        if (normalized == 'false' || normalized == '0' || normalized == 'no') {
          _cachedEnableDohResolver = false;
          return false;
        }
      }

      _cachedEnableDohResolver = true;
      return true;
    } catch (e, stackTrace) {
      _logger.warning('Failed to get DoH resolver enabled flag', e, stackTrace);
      _cachedEnableDohResolver = true;
      return true;
    }
  }

  static bool getCachedEnableDohResolver() {
    return _cachedEnableDohResolver;
  }

  static Future<String?> getBootstrapRemoteUrl() async {
    try {
      final config = await ConfigFileLoader.loadFromFile();
      return config.bootstrapConfig.remoteUrl;
    } catch (_) {
      return null;
    }
  }
}
