import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Pointer;

import 'package:animations/animations.dart';
import 'package:dio/dio.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/widgets/dialog.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:material_color_utilities/palettes/core_palette.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common/common.dart';
import 'common/runtime_dns_config.dart';
import 'controller.dart';
import 'models/models.dart';
import 'package:fl_clash/xboard/config/utils/config_file_loader.dart';
import 'package:fl_clash/xboard/infrastructure/network/direct_domain_matcher.dart';

typedef UpdateTasks = List<FutureOr Function()>;

Map<String, dynamic>? normalizeRuntimeEchOptions(
  Map echOpts, {
  String fallbackConfigList = defaultClientEchConfigList,
  String fallbackQueryServerName = defaultClientEchQueryServerName,
  String fallbackForceQuery = defaultClientEchForceQuery,
}) {
  final enabledValue = _firstEchValue(echOpts, const ['enable', 'enabled']);
  if (_isExplicitFalse(enabledValue)) {
    return null;
  }

  var config = _echString(_firstEchValue(echOpts, const [
    'config',
    'echConfig',
  ]));
  var configList = _echString(_firstEchValue(echOpts, const [
    'config-list',
    'config_list',
    'configList',
    'ech-config-list',
    'ech_config_list',
    'echConfigList',
  ]));
  var queryServerName = _echString(_firstEchValue(echOpts, const [
    'query-server-name',
    'query_server_name',
    'queryServerName',
    'ech-query-server-name',
    'ech_query_server_name',
    'echQueryServerName',
  ]));
  final configuredForceQuery = _normalizeEchForceQuery(
    _echString(_firstEchValue(
      echOpts,
      const [
        'force-query',
        'force_query',
        'forceQuery',
        'ech-force-query',
        'ech_force_query',
        'echForceQuery',
      ],
    )),
  );
  final forceQuery = configuredForceQuery.isNotEmpty
      ? configuredForceQuery
      : _normalizeEchForceQuery(fallbackForceQuery);

  if (_isDisabledEchValue(config) || _isDisabledEchValue(configList)) {
    return null;
  }

  final combinedConfig = _splitCombinedEchValue(config);
  if (combinedConfig != null) {
    queryServerName =
        queryServerName.isEmpty ? combinedConfig.$1 : queryServerName;
    config = '';
    configList = combinedConfig.$2;
  }
  final combinedConfigList = _splitCombinedEchValue(configList);
  if (combinedConfigList != null) {
    queryServerName =
        queryServerName.isEmpty ? combinedConfigList.$1 : queryServerName;
    configList = combinedConfigList.$2;
  }

  if (config.startsWith('+') && _looksLikeEchResolver(config.substring(1))) {
    configList = config.substring(1).trim();
    config = '';
  }
  if (configList.startsWith('+') &&
      _looksLikeEchResolver(configList.substring(1))) {
    configList = configList.substring(1).trim();
  }

  if (_looksLikeEchResolver(config)) {
    configList = config;
    config = '';
  }

  if (configList.isNotEmpty && !_looksLikeEchResolver(configList)) {
    config = configList;
    configList = '';
  }

  if (config.isNotEmpty) {
    return {
      'enable': true,
      'config': config,
    };
  }

  if (configList.isNotEmpty) {
    final resolvedQueryServerName = queryServerName.isNotEmpty
        ? queryServerName
        : fallbackQueryServerName.trim();
    return {
      'enable': true,
      'config-list': configList,
      if (forceQuery.isNotEmpty) 'force-query': forceQuery,
      if (resolvedQueryServerName.isNotEmpty)
        'query-server-name': resolvedQueryServerName,
    };
  }

  final fallbackResolver = fallbackConfigList.trim();
  final resolvedQueryServerName = queryServerName.isNotEmpty
      ? queryServerName
      : fallbackQueryServerName.trim();
  if (resolvedQueryServerName.isNotEmpty &&
      _looksLikeEchResolver(fallbackResolver)) {
    return {
      'enable': true,
      'config-list': fallbackResolver,
      if (forceQuery.isNotEmpty) 'force-query': forceQuery,
      'query-server-name': resolvedQueryServerName,
    };
  }

  return null;
}

Object? _firstEchValue(Map source, List<String> keys) {
  for (final key in keys) {
    if (source.containsKey(key)) {
      return source[key];
    }
  }

  final normalizedKeys = keys.map(_normalizeEchKey).toSet();
  for (final entry in source.entries) {
    if (normalizedKeys.contains(_normalizeEchKey(entry.key.toString()))) {
      return entry.value;
    }
  }
  return null;
}

String _normalizeEchKey(String value) {
  return value.toLowerCase().replaceAll('-', '').replaceAll('_', '');
}

String _echString(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is Iterable) {
    return value.map((item) => item.toString().trim()).join('\n').trim();
  }
  return value.toString().trim();
}

String _normalizeEchForceQuery(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'full' || 'half' || 'none' => normalized,
    _ => '',
  };
}

bool _isExplicitFalse(Object? value) {
  if (value is bool) {
    return !value;
  }
  return _isDisabledEchValue(_echString(value));
}

bool _isDisabledEchValue(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'false' ||
      normalized == 'none' ||
      normalized == 'off' ||
      normalized == '0';
}

bool _looksLikeEchResolver(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('https://') ||
      normalized.startsWith('tls://') ||
      normalized.startsWith('quic://') ||
      normalized.startsWith('dhcp://') ||
      normalized.startsWith('system://');
}

(String, String)? _splitCombinedEchValue(String value) {
  final trimmed = value.trim();
  final splitIndex = trimmed.indexOf('+');
  if (splitIndex <= 0 || splitIndex == trimmed.length - 1) {
    return null;
  }

  final queryServerName = trimmed.substring(0, splitIndex).trim();
  final configList = trimmed.substring(splitIndex + 1).trim();
  if (queryServerName.isEmpty || !_looksLikeEchResolver(configList)) {
    return null;
  }
  return (queryServerName, configList);
}

class GlobalState {
  static GlobalState? _instance;
  Map<CacheTag, double> cacheScrollPosition = {};
  Map<CacheTag, FixedMap<String, double>> cacheHeightMap = {};
  bool isService = false;
  Timer? timer;
  Timer? groupsUpdateTimer;
  late Config config;
  late AppState appState;
  bool isPre = true;
  String? coreSHA256;
  late PackageInfo packageInfo;
  Function? updateCurrentDelayDebounce;
  late Measure measure;
  late CommonTheme theme;
  late Color accentColor;
  CorePalette? corePalette;
  DateTime? startTime;
  UpdateTasks tasks = [];
  final navigatorKey = GlobalKey<NavigatorState>();
  AppController? _appController;
  GlobalKey<CommonScaffoldState> homeScaffoldKey = GlobalKey();
  bool isInit = false;

  bool get isStart => startTime != null && startTime!.isBeforeNow;

  AppController get appController => _appController!;

  set appController(AppController appController) {
    _appController = appController;
    isInit = true;
  }

  GlobalState._internal();

  factory GlobalState() {
    _instance ??= GlobalState._internal();
    return _instance!;
  }

  initApp(int version) async {
    coreSHA256 = const String.fromEnvironment("CORE_SHA256");
    isPre = const String.fromEnvironment("APP_ENV") != 'stable';
    appState = AppState(
      version: version,
      viewSize: Size.zero,
      requests: FixedList(maxLength),
      logs: FixedList(maxLength),
      traffics: FixedList(30),
      totalTraffic: Traffic(),
    );
    await _initDynamicColor();
    await init();
  }

  _initDynamicColor() async {
    try {
      corePalette = await DynamicColorPlugin.getCorePalette();
      accentColor = await DynamicColorPlugin.getAccentColor() ??
          Color(defaultPrimaryColor);
    } catch (_) {}
  }

  init() async {
    packageInfo = await PackageInfo.fromPlatform();
    config = await preferences.getConfig() ??
        Config(
          themeProps: defaultThemeProps,
        );
    await globalState.migrateOldData(config);
    await _mergeForceDirectDomainsIntoBypassList();
    await AppLocalizations.load(
      utils.getLocaleForString(config.appSetting.locale) ??
          WidgetsBinding.instance.platformDispatcher.locale,
    );
  }

  Future<void> _mergeForceDirectDomainsIntoBypassList() async {
    try {
      final forceDirectDomains =
          await ConfigFileLoaderHelper.getForceDirectDomains();
      if (forceDirectDomains.isEmpty) {
        return;
      }

      final currentBypass = config.networkProps.bypassDomain;
      final mergedBypass = _mergeBypassDomainWithForceDirect(
        currentBypass,
        forceDirectDomains,
      );

      if (_sameStringList(currentBypass, mergedBypass)) {
        return;
      }

      config = config.copyWith(
        networkProps: config.networkProps.copyWith(
          bypassDomain: mergedBypass,
        ),
      );
    } catch (_) {}
  }

  List<String> _mergeBypassDomainWithForceDirect(
    List<String> bypassDomain,
    List<String> forceDirectDomains,
  ) {
    final merged = List<String>.from(bypassDomain);
    final existing = <String>{
      ...bypassDomain
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty),
    };

    final hosts = DirectDomainMatcher.normalizeDomainList(forceDirectDomains);
    void addPattern(String pattern) {
      final key = pattern.trim().toLowerCase();
      if (key.isEmpty || !existing.add(key)) {
        return;
      }
      merged.add(pattern);
    }

    for (final host in hosts) {
      addPattern(host);
      addPattern('*.$host');
    }

    return merged;
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  List<String> _normalizeCustomRuleDomains(Iterable<String> domains) {
    final normalized = DirectDomainMatcher.normalizeDomainList(domains);
    if (normalized.isNotEmpty) {
      return normalized;
    }

    final fallback = <String>{};
    for (final domain in domains) {
      final trimmed = domain.trim().toLowerCase();
      if (trimmed.isNotEmpty) {
        fallback.add(trimmed);
      }
    }
    return fallback.toList();
  }

  String? _resolveProxyRuleTarget(
    Map<String, dynamic> rawConfig,
    Profile profile,
  ) {
    final groups = ((rawConfig["proxy-groups"] ?? const []) as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (groups.isEmpty) {
      return null;
    }

    final groupNames = <String>[];
    String? firstVisibleGroup;
    for (final group in groups) {
      final name = (group["name"] ?? "").toString().trim();
      if (name.isEmpty) {
        continue;
      }
      groupNames.add(name);
      final isHidden = group["hidden"] == true;
      if (!isHidden && name != GroupName.GLOBAL.name) {
        firstVisibleGroup ??= name;
      }
    }

    if (config.patchClashConfig.mode == Mode.global &&
        groupNames.contains(GroupName.GLOBAL.name)) {
      return GroupName.GLOBAL.name;
    }

    final currentGroupName = profile.currentGroupName?.trim();
    if (currentGroupName != null &&
        currentGroupName.isNotEmpty &&
        groupNames.contains(currentGroupName) &&
        currentGroupName != GroupName.GLOBAL.name) {
      return currentGroupName;
    }

    for (final groupName in profile.selectedMap.keys) {
      if (groupName.isNotEmpty &&
          groupNames.contains(groupName) &&
          groupName != GroupName.GLOBAL.name) {
        return groupName;
      }
    }

    if (firstVisibleGroup != null) {
      return firstVisibleGroup;
    }

    if (groupNames.contains(GroupName.GLOBAL.name)) {
      return GroupName.GLOBAL.name;
    }

    return groupNames.first;
  }

  void _applyClientEchSetting(Map<String, dynamic> rawConfig) {
    final proxies = rawConfig["proxies"];
    if (proxies is! List) {
      return;
    }

    for (final proxy in proxies.whereType<Map>()) {
      if (!config.networkProps.clientEch) {
        proxy.remove("ech-opts");
        continue;
      }

      final echOpts = proxy["ech-opts"];
      if (echOpts is! Map) {
        continue;
      }

      final networkProps = config.networkProps;
      final normalized = normalizeRuntimeEchOptions(
        echOpts,
        fallbackConfigList: networkProps.clientEchConfigList,
        fallbackQueryServerName: networkProps.clientEchQueryServerName,
        fallbackForceQuery: networkProps.clientEchForceQuery,
      );
      if (normalized == null) {
        proxy.remove("ech-opts");
        continue;
      }
      proxy["ech-opts"] = normalized;
    }
  }

  List<String> _insertRulesBeforeMatch(
    List<String> rules,
    List<String> customRules,
  ) {
    if (customRules.isEmpty) {
      return rules;
    }

    final matchIndex = rules.indexWhere(
      (rule) => rule.trim().toUpperCase().startsWith("MATCH,"),
    );
    if (matchIndex == -1) {
      return [...customRules, ...rules];
    }

    return [
      ...rules.sublist(0, matchIndex),
      ...customRules,
      ...rules.sublist(matchIndex),
    ];
  }

  String get ua => config.patchClashConfig.globalUa ?? packageInfo.ua;

  startUpdateTasks([UpdateTasks? tasks]) async {
    if (timer != null && timer!.isActive == true) return;
    if (tasks != null) {
      this.tasks = tasks;
    }
    await executorUpdateTask();
    timer = Timer(const Duration(seconds: 1), () async {
      startUpdateTasks();
    });
  }

  executorUpdateTask() async {
    for (final task in tasks) {
      await task();
    }
    timer = null;
  }

  stopUpdateTasks() {
    if (timer == null || timer?.isActive == false) return;
    timer?.cancel();
    timer = null;
  }

  handleStart([UpdateTasks? tasks]) async {
    startTime ??= DateTime.now();
    await clashCore.startListener();
    await service?.startVpn();
    startUpdateTasks(tasks);
  }

  Future updateStartTime() async {
    startTime = await clashLib?.getRunTime();
  }

  Future handleStop() async {
    startTime = null;
    await clashCore.stopListener();
    await service?.stopVpn();
    stopUpdateTasks();
  }

  Future<bool?> showMessage({
    String? title,
    required InlineSpan message,
    String? confirmText,
    bool cancelable = true,
  }) async {
    return await showCommonDialog<bool>(
      child: Builder(
        builder: (context) {
          return CommonDialog(
            title: title ?? appLocalizations.tip,
            actions: [
              if (cancelable)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: Text(appLocalizations.cancel),
                ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: Text(confirmText ?? appLocalizations.confirm),
              )
            ],
            child: Container(
              width: 300,
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.labelLarge,
                    children: [message],
                  ),
                  style: const TextStyle(
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Future<Map<String, dynamic>> getProfileMap(String id) async {
  //   final profilePath = await appPath.getProfilePath(id);
  //   final res = await Isolate.run<Result<dynamic>>(() async {
  //     try {
  //       final file = File(profilePath);
  //       if (!await file.exists()) {
  //         return Result.error("");
  //       }
  //       final value = await file.readAsString();
  //       return Result.success(utils.convertYamlNode(loadYaml(value)));
  //     } catch (e) {
  //       return Result.error(e.toString());
  //     }
  //   });
  //   if (res.isSuccess) {
  //     return res.data as Map<String, dynamic>;
  //   } else {
  //     throw res.message;
  //   }
  // }

  Future<T?> showCommonDialog<T>({
    required Widget child,
    bool dismissible = true,
  }) async {
    return await showModal<T>(
      context: navigatorKey.currentState!.context,
      configuration: FadeScaleTransitionConfiguration(
        barrierColor: Colors.black38,
        barrierDismissible: dismissible,
      ),
      builder: (_) => child,
      filter: commonFilter,
    );
  }

  Future<T?> safeRun<T>(
    FutureOr<T> Function() futureFunction, {
    String? title,
    bool silence = true,
  }) async {
    try {
      final res = await futureFunction();
      return res;
    } catch (e) {
      commonPrint.log("$e");
      if (silence) {
        showNotifier(e.toString());
      } else {
        showMessage(
          title: title ?? appLocalizations.tip,
          message: TextSpan(
            text: e.toString(),
          ),
        );
      }
      return null;
    }
  }

  showNotifier(String text, {VoidCallback? onTap}) {
    if (text.isEmpty) {
      return;
    }
    navigatorKey.currentContext?.showNotifier(text, onTap: onTap);
  }

  openUrl(String url) async {
    final res = await showMessage(
      message: TextSpan(text: url),
      title: appLocalizations.externalLink,
      confirmText: appLocalizations.go,
    );
    if (res != true) {
      return;
    }
    launchUrl(Uri.parse(url));
  }

  Future<void> migrateOldData(Config config) async {
    final clashConfig = await preferences.getClashConfig();
    if (clashConfig != null) {
      config = config.copyWith(
        patchClashConfig: clashConfig,
      );
      preferences.clearClashConfig();
      preferences.saveConfig(config);
    }
  }

  CoreState getCoreState() {
    final currentProfile = config.currentProfile;
    final bypassDomain = _mergeBypassDomainWithForceDirect(
      config.networkProps.bypassDomain,
      ConfigFileLoaderHelper.getCachedForceDirectDomains(),
    );
    return CoreState(
      vpnProps: config.vpnProps,
      onlyStatisticsProxy: config.appSetting.onlyStatisticsProxy,
      currentProfileName: currentProfile?.label ?? currentProfile?.id ?? "",
      bypassDomain: bypassDomain,
    );
  }

  Future<SetupParams> getSetupParams({
    required ClashConfig pathConfig,
  }) async {
    final clashConfig = await patchRawConfig(
      patchConfig: pathConfig,
    );
    final params = SetupParams(
      config: clashConfig,
      selectedMap: config.currentProfile?.selectedMap ?? {},
      testUrl: config.appSetting.testUrl,
    );
    return params;
  }

  Future<Map<String, dynamic>> patchRawConfig({
    required ClashConfig patchConfig,
  }) async {
    final profile = config.currentProfile;
    if (profile == null) {
      throw "未选择配置，无法生成运行配置，请先选择一个配置/订阅";
    }
    final profileId = profile.id;
    final configMap = await getProfileConfig(profileId);
    final rawConfig = await handleEvaluate(configMap);
    final realPatchConfig = patchConfig.copyWith(
      tun: patchConfig.tun.getRealTun(config.networkProps.routeMode),
    );
    rawConfig["external-controller"] = realPatchConfig.externalController.value;
    rawConfig["external-ui"] = "";
    rawConfig["interface-name"] = "";
    rawConfig["external-ui-url"] = "";
    rawConfig["tcp-concurrent"] = realPatchConfig.tcpConcurrent;
    rawConfig["unified-delay"] = realPatchConfig.unifiedDelay;
    rawConfig["ipv6"] = realPatchConfig.ipv6;
    rawConfig["log-level"] = realPatchConfig.logLevel.name;
    rawConfig["port"] = 0;
    rawConfig["socks-port"] = 0;
    rawConfig["keep-alive-interval"] = realPatchConfig.keepAliveInterval;
    rawConfig["mixed-port"] = realPatchConfig.mixedPort;
    rawConfig["port"] = realPatchConfig.port;
    rawConfig["socks-port"] = realPatchConfig.socksPort;
    rawConfig["redir-port"] = realPatchConfig.redirPort;
    rawConfig["tproxy-port"] = realPatchConfig.tproxyPort;
    rawConfig["find-process-mode"] = realPatchConfig.findProcessMode.name;
    rawConfig["allow-lan"] = realPatchConfig.allowLan;
    rawConfig["mode"] = realPatchConfig.mode.name;
    if (rawConfig["tun"] == null) {
      rawConfig["tun"] = {};
    }
    rawConfig["tun"]["enable"] = realPatchConfig.tun.enable;
    rawConfig["tun"]["device"] = realPatchConfig.tun.device;
    rawConfig["tun"]["dns-hijack"] = realPatchConfig.tun.dnsHijack;
    rawConfig["tun"]["stack"] = realPatchConfig.tun.stack.name;
    rawConfig["tun"]["route-address"] = realPatchConfig.tun.routeAddress;
    rawConfig["tun"]["auto-route"] = realPatchConfig.tun.autoRoute;
    rawConfig["geodata-loader"] = realPatchConfig.geodataLoader.name;
    if (rawConfig["sniffer"]?["sniff"] != null) {
      for (final value in (rawConfig["sniffer"]?["sniff"] as Map).values) {
        if (value["ports"] != null && value["ports"] is List) {
          value["ports"] =
              value["ports"]?.map((item) => item.toString()).toList() ?? [];
        }
      }
    }
    if (rawConfig["profile"] == null) {
      rawConfig["profile"] = {};
    }
    if (rawConfig["proxy-providers"] != null) {
      final proxyProviders = rawConfig["proxy-providers"] as Map;
      for (final key in proxyProviders.keys) {
        final proxyProvider = proxyProviders[key];
        if (proxyProvider["type"] != "http") {
          continue;
        }
        if (proxyProvider["url"] != null) {
          proxyProvider["path"] = await appPath.getProvidersFilePath(
            profile.id,
            "proxies",
            proxyProvider["url"],
          );
        }
      }
    }

    if (rawConfig["rule-providers"] != null) {
      final ruleProviders = rawConfig["rule-providers"] as Map;
      for (final key in ruleProviders.keys) {
        final ruleProvider = ruleProviders[key];
        if (ruleProvider["type"] != "http") {
          continue;
        }
        if (ruleProvider["url"] != null) {
          ruleProvider["path"] = await appPath.getProvidersFilePath(
            profile.id,
            "rules",
            ruleProvider["url"],
          );
        }
      }
    }

    rawConfig["profile"]["store-selected"] = false;
    rawConfig["geox-url"] = realPatchConfig.geoXUrl.toJson();
    rawConfig["global-ua"] = realPatchConfig.globalUa;
    if (rawConfig["hosts"] == null) {
      rawConfig["hosts"] = {};
    }
    for (final host in realPatchConfig.hosts.entries) {
      rawConfig["hosts"][host.key] = host.value.splitByMultipleSeparators;
    }
    rawConfig["dns"] = buildRuntimeDnsConfig(
      profileDns: rawConfig["dns"] is Map
          ? Map<String, dynamic>.from(rawConfig["dns"] as Map)
          : null,
      patchDns: realPatchConfig.dns,
      overrideDns: globalState.config.overrideDns,
    );
    _applyClientEchSetting(rawConfig);
    var rules = <String>[];
    if (rawConfig["rules"] is List) {
      rules = List<String>.from(
        (rawConfig["rules"] as List).whereType<String>(),
      );
    }
    rawConfig.remove("rules");

    final overrideData = profile.overrideData;
    if (overrideData.enable && config.scriptProps.currentScript == null) {
      if (overrideData.rule.type == OverrideRuleType.override) {
        rules = overrideData.runningRule;
      } else {
        rules = [...overrideData.runningRule, ...rules];
      }
    }

    final forceDirectDomains =
        await ConfigFileLoaderHelper.getForceDirectDomains();
    if (forceDirectDomains.isNotEmpty) {
      final forceDirectRules = <String>[];
      final currentRuleSet = <String>{
        ...rules
            .whereType<String>()
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty),
      };

      for (final host
          in DirectDomainMatcher.normalizeDomainList(forceDirectDomains)) {
        final rule = 'DOMAIN-SUFFIX,$host,DIRECT';
        final key = rule.toLowerCase();
        if (currentRuleSet.add(key)) {
          forceDirectRules.add(rule);
        }
      }

      if (forceDirectRules.isNotEmpty) {
        rules = [...forceDirectRules, ...rules];
      }
    }

    final customRules = <String>[];
    final currentRuleSet = <String>{
      ...rules
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty),
    };

    for (final host in _normalizeCustomRuleDomains(
      config.networkProps.customDirectDomains,
    )) {
      final rule = "DOMAIN-SUFFIX,$host,DIRECT";
      final key = rule.toLowerCase();
      if (currentRuleSet.add(key)) {
        customRules.add(rule);
      }
    }

    final proxyRuleTarget = _resolveProxyRuleTarget(rawConfig, profile);
    if (proxyRuleTarget != null) {
      for (final host in _normalizeCustomRuleDomains(
        config.networkProps.customProxyDomains,
      )) {
        final rule = "DOMAIN-SUFFIX,$host,$proxyRuleTarget";
        final key = rule.toLowerCase();
        if (currentRuleSet.add(key)) {
          customRules.add(rule);
        }
      }
    }

    rules = _insertRulesBeforeMatch(rules, customRules);

    rawConfig["rule"] = rules;
    return rawConfig;
  }

  Future<Map<String, dynamic>> getProfileConfig(String profileId) async {
    final configMap = await switch (clashLibHandler != null) {
      true => clashLibHandler!.getConfig(profileId),
      false => clashCore.getConfig(profileId),
    };
    if (configMap.isEmpty) {
      throw "配置内容为空（可能还未下载完成/文件损坏），请先更新订阅后重试";
    }
    configMap["rules"] = configMap["rule"];
    configMap.remove("rule");
    return configMap;
  }

  Future<Map<String, dynamic>> handleEvaluate(
    Map<String, dynamic> config,
  ) async {
    final currentScript = globalState.config.scriptProps.currentScript;
    if (currentScript == null) {
      return config;
    }
    if (config["proxy-providers"] == null) {
      config["proxy-providers"] = {};
    }
    final configJs = json.encode(config);
    final runtime = getJavascriptRuntime();
    final res = await runtime.evaluateAsync("""
      ${currentScript.content}
      main($configJs)
    """);
    if (res.isError) {
      throw res.stringResult;
    }
    final value = switch (res.rawResult is Pointer) {
      true => runtime.convertValue<Map<String, dynamic>>(res),
      false => Map<String, dynamic>.from(res.rawResult),
    };
    return value ?? config;
  }
}

final globalState = GlobalState();

class DetectionState {
  static DetectionState? _instance;
  bool? _preIsStart;
  Timer? _setTimeoutTimer;
  CancelToken? cancelToken;

  final state = ValueNotifier<NetworkDetectionState>(
    const NetworkDetectionState(
      isTesting: false,
      isLoading: true,
      ipInfo: null,
    ),
  );

  DetectionState._internal();

  factory DetectionState() {
    _instance ??= DetectionState._internal();
    return _instance!;
  }

  startCheck() {
    debouncer.call(
      FunctionTag.checkIp,
      _checkIp,
      duration: Duration(
        milliseconds: 1200,
      ),
    );
  }

  _checkIp() async {
    final appState = globalState.appState;
    final isInit = appState.isInit;
    if (!isInit) return;
    final isStart = appState.runTime != null;
    if (_preIsStart == false &&
        _preIsStart == isStart &&
        state.value.ipInfo != null) {
      return;
    }
    _clearSetTimeoutTimer();
    state.value = state.value.copyWith(
      isLoading: true,
      ipInfo: null,
    );
    _preIsStart = isStart;
    if (cancelToken != null) {
      cancelToken!.cancel();
      cancelToken = null;
    }
    cancelToken = CancelToken();
    state.value = state.value.copyWith(
      isTesting: true,
    );
    final res = await request.checkIp(cancelToken: cancelToken);
    if (res.isError) {
      state.value = state.value.copyWith(
        isLoading: true,
        ipInfo: null,
      );
      return;
    }
    final ipInfo = res.data;
    state.value = state.value.copyWith(
      isTesting: false,
    );
    if (ipInfo != null) {
      state.value = state.value.copyWith(
        isLoading: false,
        ipInfo: ipInfo,
      );
      return;
    }
    _clearSetTimeoutTimer();
    _setTimeoutTimer = Timer(const Duration(milliseconds: 300), () {
      state.value = state.value.copyWith(
        isLoading: false,
        ipInfo: null,
      );
    });
  }

  _clearSetTimeoutTimer() {
    if (_setTimeoutTimer != null) {
      _setTimeoutTimer?.cancel();
      _setTimeoutTimer = null;
    }
  }
}

final detectionState = DetectionState();
