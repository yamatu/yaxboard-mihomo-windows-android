import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/archive.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common/common.dart';
import 'models/models.dart';
import 'views/profiles/override_profile.dart';

class AppController {
  int? lastProfileModified;

  final BuildContext context;
  final WidgetRef _ref;

  AppController(this.context, WidgetRef ref) : _ref = ref;

  setupClashConfigDebounce() {
    debouncer.call(FunctionTag.setupClashConfig, () async {
      await setupClashConfig();
    });
  }

  updateClashConfigDebounce() {
    // 这里直接调用内部的 _updateClashConfig, 避免依赖 homeScaffoldKey 的 UI 状态,
    // 保证托盘、快捷键、XBoard 小组件等任意入口都可以热更新核心配置
    debouncer.call(FunctionTag.updateClashConfig, () async {
      await _updateClashConfig();
    });
  }

  updateGroupsDebounce() {
    debouncer.call(FunctionTag.updateGroups, updateGroups);
  }

  addCheckIpNumDebounce() {
    debouncer.call(FunctionTag.addCheckIpNum, () {
      _ref.read(checkIpNumProvider.notifier).add();
    });
  }

  applyProfileDebounce({
    bool silence = false,
  }) {
    debouncer.call(FunctionTag.applyProfile, (silence) {
      applyProfile(silence: silence);
    }, args: [silence]);
  }

  savePreferencesDebounce() {
    debouncer.call(FunctionTag.savePreferences, savePreferences);
  }

  changeProxyDebounce(String groupName, String proxyName) {
    debouncer.call(FunctionTag.changeProxy,
        (String groupName, String proxyName) async {
      await changeProxy(
        groupName: groupName,
        proxyName: proxyName,
      );
      await updateGroups();
    }, args: [groupName, proxyName]);
  }

  restartCore() async {
    commonPrint.log("restart core");
    await clashService?.reStart();
    await _initCore();
    if (_ref.read(runTimeProvider.notifier).isStart) {
      await globalState.handleStart();
    }
  }

  updateStatus(bool isStart) async {
    if (isStart) {
      // 桌面端兜底：用户只点击“启动代理”但未开启系统代理开关时，
      // 会导致系统代理不会自动设置（需要手动去系统设置开启）。
      // 这里在启动时自动打开开关，确保可用性；用户仍可在设置中手动关闭。
      if (system.isDesktop) {
        final enabled =
            _ref.read(networkSettingProvider.select((s) => s.systemProxy));
        if (!enabled) {
          _ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(systemProxy: true),
              );
          // 尽量同步 vpnProps，避免配置里出现两个开关值不一致。
          _ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(systemProxy: true),
              );
          commonPrint.log("[Proxy] 启动代理时自动开启系统代理开关");
        }
      }

      // Android/部分设备：在配置未就绪（节点未加载/配置未下发）时先启动 listener
      // 可能导致底层崩溃。这里调整为：先下发配置，再启动核心。
      final profile = _ref.read(currentProfileProvider);
      if (profile == null) {
        globalState.showNotifier("未选择配置，无法启动代理");
        return;
      }

      try {
        // 若本地尚无配置文件会触发拉取；若配置不可用会抛错。
        await profile.checkAndUpdate();
        await _applyProfile();
      } catch (e) {
        commonPrint.log("[Core] 启动前下发配置失败：$e");
        globalState.showNotifier("启动失败：配置未就绪，请先更新订阅/稍后重试\n$e");
        return;
      }

      await globalState.handleStart([
        updateRunTime,
        updateTraffic,
      ]);
    } else {
      await globalState.handleStop();

      // Desktop (especially Windows): stopping core should also restore system proxy.
      // Some environments (e.g. TUN on/off switches, rapid toggles) may miss the
      // ProxyManager listener; do a best-effort fallback here.
      if (system.isDesktop) {
        final systemProxyEnabled =
            _ref.read(networkSettingProvider.select((s) => s.systemProxy));
        if (systemProxyEnabled) {
          try {
            await proxy?.stopProxy();
          } catch (_) {
            // ignore
          }
        }
      }

      await clashCore.resetTraffic();
      _ref.read(trafficsProvider.notifier).clear();
      _ref.read(totalTrafficProvider.notifier).value = Traffic();
      _ref.read(runTimeProvider.notifier).value = null;
      addCheckIpNumDebounce();
    }
  }

  updateRunTime() {
    final startTime = globalState.startTime;
    if (startTime != null) {
      final startTimeStamp = startTime.millisecondsSinceEpoch;
      final nowTimeStamp = DateTime.now().millisecondsSinceEpoch;
      _ref.read(runTimeProvider.notifier).value = nowTimeStamp - startTimeStamp;
    } else {
      _ref.read(runTimeProvider.notifier).value = null;
    }
  }

  updateTraffic() async {
    final traffic = await clashCore.getTraffic();
    _ref.read(trafficsProvider.notifier).addTraffic(traffic);
    _ref.read(totalTrafficProvider.notifier).value =
        await clashCore.getTotalTraffic();
  }

  addProfile(Profile profile) async {
    _ref.read(profilesProvider.notifier).setProfile(profile);
    if (_ref.read(currentProfileIdProvider) != null) return;
    _ref.read(currentProfileIdProvider.notifier).value = profile.id;
  }

  deleteProfile(String id) async {
    _ref.read(profilesProvider.notifier).deleteProfileById(id);
    clearEffect(id);
    if (globalState.config.currentProfileId == id) {
      final profiles = globalState.config.profiles;
      final currentProfileId = _ref.read(currentProfileIdProvider.notifier);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        currentProfileId.value = updateId;
      } else {
        currentProfileId.value = null;
        updateStatus(false);
      }
    }
  }

  updateProviders() async {
    _ref.read(providersProvider.notifier).value =
        await clashCore.getExternalProviders();
  }

  updateLocalIp() async {
    _ref.read(localIpProvider.notifier).value = null;
    await Future.delayed(commonDuration);
    _ref.read(localIpProvider.notifier).value = await utils.getLocalIpAddress();
  }

  Future<void> updateProfile(Profile profile) async {
    final newProfile = await profile.update();
    _ref
        .read(profilesProvider.notifier)
        .setProfile(newProfile.copyWith(isUpdating: false));
    if (profile.id == _ref.read(currentProfileIdProvider)) {
      applyProfileDebounce(silence: true);
    }
  }

  setProfile(Profile profile) {
    _ref.read(profilesProvider.notifier).setProfile(profile);
  }

  setProfileAndAutoApply(Profile profile) {
    _ref.read(profilesProvider.notifier).setProfile(profile);
    if (profile.id == _ref.read(currentProfileIdProvider)) {
      applyProfileDebounce(silence: true);
    }
  }

  setProfiles(List<Profile> profiles) {
    _ref.read(profilesProvider.notifier).value = profiles;
  }

  addLog(Log log) {
    _ref.read(logsProvider).add(log);
  }

  updateOrAddHotKeyAction(HotKeyAction hotKeyAction) {
    final hotKeyActions = _ref.read(hotKeyActionsProvider);
    final index =
        hotKeyActions.indexWhere((item) => item.action == hotKeyAction.action);
    if (index == -1) {
      _ref.read(hotKeyActionsProvider.notifier).value = List.from(hotKeyActions)
        ..add(hotKeyAction);
    } else {
      _ref.read(hotKeyActionsProvider.notifier).value = List.from(hotKeyActions)
        ..[index] = hotKeyAction;
    }

    _ref.read(hotKeyActionsProvider.notifier).value = index == -1
        ? (List.from(hotKeyActions)..add(hotKeyAction))
        : (List.from(hotKeyActions)..[index] = hotKeyAction);
  }

  List<Group> getCurrentGroups() {
    return _ref.read(currentGroupsStateProvider.select((state) => state.value));
  }

  String getRealTestUrl(String? url) {
    return _ref.read(getRealTestUrlProvider(url));
  }

  int getProxiesColumns() {
    return _ref.read(getProxiesColumnsProvider);
  }

  addSortNum() {
    return _ref.read(sortNumProvider.notifier).add();
  }

  getCurrentGroupName() {
    final currentGroupName = _ref.read(currentProfileProvider.select(
      (state) => state?.currentGroupName,
    ));
    return currentGroupName;
  }

  ProxyCardState getProxyCardState(proxyName) {
    return _ref.read(getProxyCardStateProvider(proxyName));
  }

  getSelectedProxyName(groupName) {
    return _ref.read(getSelectedProxyNameProvider(groupName));
  }

  updateCurrentGroupName(String groupName) {
    final profile = _ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) {
      return;
    }
    setProfile(
      profile.copyWith(currentGroupName: groupName),
    );
  }

  Future<void> updateClashConfig() async {
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    await commonScaffoldState?.loadingRun(() async {
      await _updateClashConfig();
    });
  }

  Future<void> _updateClashConfig() async {
    final updateParams = _ref.read(updateParamsProvider);
    final enableTun = updateParams.tun.enable;
    // 记录当前实际的 TUN 启用状态, 用于判断是否是“首次开启 TUN”
    final prevRealTunEnable = _ref.read(realTunEnableProvider);
    // 先根据当前的 TUN 开关请求/确认管理员权限, 并在内部同步 realTunEnable 状态
    final res = await _requestAdmin(enableTun);
    if (res.isError) {
      // 授权失败时不再继续下发配置, 避免进入半开启状态
      return;
    }
    final realTunEnable = _ref.read(realTunEnableProvider);
    // 如果是“首次从未开启 -> 开启 TUN”, _requestAdmin 内部已经执行了 restartCore + 完整的
    // 配置下发(_initCore/_applyProfile/_setupClashConfig)。此时立刻再调用一次 updateConfig
    // 往往发生在核心刚重启、控制通道还未稳定的时刻, 容易触发 Windows 下的 10054 连接异常,
    // 导致首次开启 TUN 时卡死或退出异常。这里直接跳过本轮增量更新, 交给刚刚执行的完整
    // setupConfig 负责应用最新配置, 可以显著减小首启 TUN 的不稳定行为。
    final isFirstEnableTun =
        enableTun && prevRealTunEnable != true && res.isSuccess;
    if (isFirstEnableTun) {
      return;
    }
    final message = await clashCore.updateConfig(
      updateParams.copyWith.tun(
        enable: realTunEnable,
      ),
    );
    if (message.isNotEmpty) throw message;
  }

  /// 处理桌面端 TUN 模式所需的管理员权限/Helper 服务。
  ///
  /// - [enableTun] 为 true 表示希望开启 TUN；false 表示关闭 TUN。
  /// - 内部统一维护 [realTunEnableProvider]，避免出现“配置里是打开的但内核实际没开”的半开启状态。
  /// - Windows/macOS/Linux 首次开启 TUN 时会弹出提权/注册 Helper 的流程，并在成功后重启核心。
  Future<Result<bool>> _requestAdmin(bool enableTun) async {
    // 如果不需要开启 TUN, 直接同步状态并返回
    if (!enableTun) {
      _ref.read(realTunEnableProvider.notifier).value = false;
      return Result.success(false);
    }

    // 需要开启 TUN
    var realTunEnable = _ref.read(realTunEnableProvider);

    // 已经是开启状态, 直接返回
    if (realTunEnable == true) {
      return Result.success(true);
    }

    // 如果系统层面已经具备管理员权限/Helper 服务在运行, 直接标记为已启用
    if (await system.checkIsAdmin()) {
      _ref.read(realTunEnableProvider.notifier).value = true;
      return Result.success(true);
    }

    // 尝试申请管理员权限/注册 Helper
    final code = await system.authorizeCore();
    switch (code) {
      case AuthorizeCode.success:
        // 提权成功, 标记并重启核心, 让 TUN 能够生效
      _ref.read(realTunEnableProvider.notifier).value = true;
      await restartCore();
      return Result.success(true);
      case AuthorizeCode.none:
        // 用户取消授权, 回退为未开启 TUN
      _ref.read(realTunEnableProvider.notifier).value = false;
      return Result.success(false);
      case AuthorizeCode.error:
        // 授权失败, 标记为未开启并返回错误, 上层不再继续调用 updateConfig/setupConfig
      _ref.read(realTunEnableProvider.notifier).value = false;
      return Result.error("authorize failed");
    }
  }

  /// 根据当前 Profile 中保存的 selectedMap 重新恢复各个分组的手动选中节点
  /// 这样在重新应用订阅 / 重启应用后, 仍然可以保持用户之前手动选择的节点
  Future<void> _restoreSelectedProxies() async {
    try {
      final selectedMap = _ref.read(selectedMapProvider);
      if (selectedMap.isEmpty) {
        return;
      }
      for (final entry in selectedMap.entries) {
        final groupName = entry.key;
        final proxyName = entry.value;
        if (groupName.isEmpty || proxyName.isEmpty) {
          continue;
        }
        try {
          await clashCore.changeProxy(
            ChangeProxyParams(
              groupName: groupName,
              proxyName: proxyName,
            ),
          );
        } catch (e) {
          commonPrint.log(
            "restore proxy failed: $groupName -> $proxyName, $e",
          );
        }
      }
    } catch (e) {
      commonPrint.log("restore selected proxies error: $e");
    }
  }

  Future<void> setupClashConfig() async {
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    await commonScaffoldState?.loadingRun(() async {
      await _setupClashConfig();
    });
  }

  _setupClashConfig() async {
    await _ref.read(currentProfileProvider)?.checkAndUpdate();
    final patchConfig = _ref.read(patchClashConfigProvider);
    final res = await _requestAdmin(patchConfig.tun.enable);
    if (res.isError) {
      throw res.message.isNotEmpty ? res.message : "授权失败，无法应用配置";
    }
    final realTunEnable = _ref.read(realTunEnableProvider);
    final realPatchConfig = patchConfig.copyWith.tun(enable: realTunEnable);
    final params = await globalState.getSetupParams(
      pathConfig: realPatchConfig,
    );
    final message = await clashCore.setupConfig(params);
    lastProfileModified = await _ref.read(
      currentProfileProvider.select(
        (state) => state?.profileLastModified,
      ),
    );
    if (message.isNotEmpty) {
      throw message;
    }
  }

  Future _applyProfile() async {
    await clashCore.requestGc();
    await _setupClashConfig();
    // 重新应用配置后优先根据 selectedMap 恢复用户手动选择的节点,
    // 避免订阅更新或应用重启后又回到自动选择节点
    await _restoreSelectedProxies();
    await updateGroups();
    await updateProviders();
  }

  Future applyProfile({bool silence = false}) async {
    if (silence) {
      await _applyProfile();
    } else {
      final commonScaffoldState = globalState.homeScaffoldKey.currentState;
      if (commonScaffoldState?.mounted != true) return;
      await commonScaffoldState?.loadingRun(() async {
        await _applyProfile();
      });
    }
    addCheckIpNumDebounce();
  }

  handleChangeProfile() {
    _ref.read(delayDataSourceProvider.notifier).value = {};
    applyProfile();
    _ref.read(logsProvider.notifier).value = FixedList(500);
    _ref.read(requestsProvider.notifier).value = FixedList(500);
    globalState.cacheHeightMap = {};
    globalState.cacheScrollPosition = {};
  }

  updateBrightness(Brightness brightness) {
    _ref.read(appBrightnessProvider.notifier).value = brightness;
  }

  autoUpdateProfiles() async {
    for (final profile in _ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(
            profile.autoUpdateDuration,
          )
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        commonPrint.log(e.toString());
      }
    }
  }

  Future<void> updateGroups() async {
    try {
      _ref.read(groupsProvider.notifier).value = await retry(
        task: () async {
          return await clashCore.getProxiesGroups();
        },
        retryIf: (res) => res.isEmpty,
      );
    } catch (_) {
      _ref.read(groupsProvider.notifier).value = [];
    }
  }

  updateProfiles() async {
    for (final profile in _ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) {
        continue;
      }
      await updateProfile(profile);
    }
  }

  savePreferences() async {
    commonPrint.log("save preferences");
    await preferences.saveConfig(globalState.config);
  }

  changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    await clashCore.changeProxy(
      ChangeProxyParams(
        groupName: groupName,
        proxyName: proxyName,
      ),
    );
    if (_ref.read(appSettingProvider).closeConnections) {
      clashCore.closeConnections();
    }
    addCheckIpNumDebounce();
  }

  handleBackOrExit() async {
    if (_ref.read(backBlockProvider)) {
      return;
    }
    if (_ref.read(appSettingProvider).minimizeOnExit) {
      if (system.isDesktop) {
        await savePreferencesDebounce();
      }
      await system.back();
    } else {
      await handleExit();
    }
  }

  backBlock() {
    _ref.read(backBlockProvider.notifier).value = true;
  }

  unBackBlock() {
    _ref.read(backBlockProvider.notifier).value = false;
  }

  handleExit() async {
    try {
      await savePreferences();
      await system.setMacOSDns(true);

      // Ensure VPN/listener stopped on exit.
      try {
        await globalState.handleStop();
      } catch (_) {
        // ignore
      }

      // 用户期望：桌面端退出/关机时尽量恢复系统代理，避免残留。
      // Windows 上 StopProxy 会尽量恢复“启动前快照”。
      if (system.isDesktop) {
        try {
          await proxy?.stopProxy();
        } catch (_) {
          // ignore
        }
      }

      await clashCore.shutdown();
      await clashService?.destroy();
      // 退出前主动销毁托盘图标, 尽量避免 Windows 残留“幽灵图标”
      await tray.destroy();
    } finally {
      system.exit();
    }
  }

  Future handleClear() async {
    await preferences.clearPreferences();
    commonPrint.log("clear preferences");
    globalState.config = Config(
      themeProps: defaultThemeProps,
    );
  }

  autoCheckUpdate() async {
    if (!_ref.read(appSettingProvider).autoCheckUpdate) return;
    final res = await request.checkForUpdate();
    checkUpdateResultHandle(data: res);
  }

  checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool handleError = false,
  }) async {
    if (globalState.isPre) {
      return;
    }
    if (data != null) {
      final tagName = data['tag_name'];
      final body = data['body'];
      final submits = utils.parseReleaseBody(body);
      final textTheme = context.textTheme;
      final res = await globalState.showMessage(
        title: appLocalizations.discoverNewVersion,
        message: TextSpan(
          text: "$tagName \n",
          style: textTheme.headlineSmall,
          children: [
            TextSpan(
              text: "\n",
              style: textTheme.bodyMedium,
            ),
            for (final submit in submits)
              TextSpan(
                text: "- $submit \n",
                style: textTheme.bodyMedium,
              ),
          ],
        ),
        confirmText: appLocalizations.goDownload,
      );
      if (res != true) {
        return;
      }
      launchUrl(
        Uri.parse("https://github.com/$repository/releases/latest"),
      );
    } else if (handleError) {
      globalState.showMessage(
        title: appLocalizations.checkUpdate,
        message: TextSpan(
          text: appLocalizations.checkUpdateError,
        ),
      );
    }
  }

  _handlePreference() async {
    if (await preferences.isInit) {
      return;
    }
    final res = await globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.cacheCorrupt),
    );
    if (res == true) {
      final file = File(await appPath.sharedPreferencesPath);
      final isExists = await file.exists();
      if (isExists) {
        await file.delete();
      }
    }
    await handleExit();
  }

  Future<void> _initCore() async {
    final isInit = await clashCore.isInit;
    if (!isInit) {
      await clashCore.init();
      await clashCore.setState(
        globalState.getCoreState(),
      );
    }

    // 启动初始化阶段 UI 可能尚未挂载（homeScaffoldKey 为空），
    // 不能依赖 loadingRun，否则会导致配置未下发、节点未加载。
    // 这里直接走无 UI 依赖的内部流程，失败则记录日志并允许应用继续启动。
    try {
      await _applyProfile();
    } catch (e) {
      commonPrint.log("[Core] 初始化应用配置失败（已忽略，待用户手动重试）：$e");
    }
  }

  init() async {
    FlutterError.onError = (details) {
      commonPrint.log(details.stack.toString());
    };
    updateTray(true);
    await _initCore();
    await _initStatus();
    autoLaunch?.updateStatus(
      _ref.read(appSettingProvider).autoLaunch,
    );
    // 启动时不再自动更新所有订阅, 仅在用户在订阅页面手动点击同步按钮时更新
    // autoUpdateProfiles();
    autoCheckUpdate();
    if (!_ref.read(appSettingProvider).silentLaunch) {
      window?.show();
    } else {
      window?.hide();
    }
    await _handlePreference();
    await _handlerDisclaimer();
    _ref.read(initProvider.notifier).value = true;
  }

  _initStatus() async {
    if (Platform.isAndroid) {
      await globalState.updateStartTime();
    }
    final status = globalState.isStart == true
        ? true
        : _ref.read(appSettingProvider).autoRun;

    await updateStatus(status);
    if (!status) {
      addCheckIpNumDebounce();
    }
  }

  setDelay(Delay delay) {
    _ref.read(delayDataSourceProvider.notifier).setDelay(delay);
  }

  toPage(PageLabel pageLabel) {
    _ref.read(currentPageLabelProvider.notifier).value = pageLabel;
  }

  toProfiles() {
    toPage(PageLabel.profiles);
  }

  initLink() {
    linkManager.initAppLinksListen(
      (url) async {
        final res = await globalState.showMessage(
          title: "${appLocalizations.add}${appLocalizations.profile}",
          message: TextSpan(
            children: [
              TextSpan(text: appLocalizations.doYouWantToPass),
              TextSpan(
                text: " $url ",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: Theme.of(context).colorScheme.primary,
                ),
              ),
              TextSpan(
                  text:
                      "${appLocalizations.create}${appLocalizations.profile}"),
            ],
          ),
        );

        if (res != true) {
          return;
        }
        addProfileFormURL(url);
      },
    );
  }

  Future<bool> showDisclaimer() async {
    return await globalState.showCommonDialog<bool>(
          dismissible: false,
          child: CommonDialog(
            title: appLocalizations.disclaimer,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop<bool>(false);
                },
                child: Text(appLocalizations.exit),
              ),
              TextButton(
                onPressed: () {
                  _ref.read(appSettingProvider.notifier).updateState(
                        (state) => state.copyWith(disclaimerAccepted: true),
                      );
                  Navigator.of(context).pop<bool>(true);
                },
                child: Text(appLocalizations.agree),
              )
            ],
            child: SelectableText(
              appLocalizations.disclaimerDesc,
            ),
          ),
        ) ??
        false;
  }

  _handlerDisclaimer() async {
    if (_ref.read(appSettingProvider).disclaimerAccepted) {
      return;
    }
    final isDisclaimerAccepted = await showDisclaimer();
    if (!isDisclaimerAccepted) {
      await handleExit();
    }
    return;
  }

  Future<void> importProfileInBackground(String url) async {
    try {
      // 先删除所有现有的URL订阅（非文件类型的订阅）
      final profiles = globalState.config.profiles;
      final urlProfiles = profiles.where((profile) => profile.type == ProfileType.url).toList();
      
      for (final profile in urlProfiles) {
        commonPrint.log('Removing existing URL profile: ${profile.label ?? profile.id}');
        deleteProfile(profile.id);
      }
      
      // 然后添加新的订阅
      final profile = await Profile.normal(
        url: url,
      ).update();
      await addProfile(profile);
      app?.tip("${appLocalizations.add} ${appLocalizations.profile}");
    } catch (e) {
      commonPrint.log('Failed to import profile in background: $e');
      app?.tip(appLocalizations.checkError);
    }
  }

  addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    toProfiles();
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    final profile = await commonScaffoldState?.loadingRun<Profile>(
      () async {
        return await Profile.normal(
          url: url,
        ).update();
      },
      title: "${appLocalizations.add}${appLocalizations.profile}",
    );
    if (profile != null) {
      await addProfile(profile);
    }
  }

  addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    final bytes = platformFile?.bytes;
    if (bytes == null) {
      return null;
    }
    if (!context.mounted) return;
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    toProfiles();
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    final profile = await commonScaffoldState?.loadingRun<Profile?>(
      () async {
        await Future.delayed(const Duration(milliseconds: 300));
        return await Profile.normal(label: platformFile?.name).saveFile(bytes);
      },
      title: "${appLocalizations.add}${appLocalizations.profile}",
    );
    if (profile != null) {
      await addProfile(profile);
    }
  }

  addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    addProfileFormURL(url);
  }

  updateViewSize(Size size) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ref.read(viewSizeProvider.notifier).value = size;
    });
  }

  setProvider(ExternalProvider? provider) {
    _ref.read(providersProvider.notifier).setProvider(provider);
  }

  List<Proxy> _sortOfName(List<Proxy> proxies) {
    return List.of(proxies)
      ..sort(
        (a, b) => utils.sortByChar(
          utils.getPinyin(a.name),
          utils.getPinyin(b.name),
        ),
      );
  }

  List<Proxy> _sortOfDelay({
    required List<Proxy> proxies,
    String? testUrl,
  }) {
    return List.of(proxies)
      ..sort(
        (a, b) {
          final aDelay = _ref.read(getDelayProvider(
            proxyName: a.name,
            testUrl: testUrl,
          ));
          final bDelay = _ref.read(
            getDelayProvider(
              proxyName: b.name,
              testUrl: testUrl,
            ),
          );
          if (aDelay == null && bDelay == null) {
            return 0;
          }
          if (aDelay == null || aDelay == -1) {
            return 1;
          }
          if (bDelay == null || bDelay == -1) {
            return -1;
          }
          return aDelay.compareTo(bDelay);
        },
      );
  }

  List<Proxy> getSortProxies(List<Proxy> proxies, [String? url]) {
    return switch (_ref.read(proxiesStyleSettingProvider).sortType) {
      ProxiesSortType.none => proxies,
      ProxiesSortType.delay => _sortOfDelay(
          proxies: proxies,
          testUrl: url,
        ),
      ProxiesSortType.name => _sortOfName(proxies),
    };
  }

  clearEffect(String profileId) async {
    final profilePath = await appPath.getProfilePath(profileId);
    final providersDirPath = await appPath.getProvidersDirPath(profileId);
    return await Isolate.run(() async {
      final profileFile = File(profilePath);
      final isExists = await profileFile.exists();
      if (isExists) {
        profileFile.delete(recursive: true);
      }
      final providersFileDir = File(providersDirPath);
      final providersFileIsExists = await providersFileDir.exists();
      if (providersFileIsExists) {
        providersFileDir.delete(recursive: true);
      }
    });
  }

  updateTun() {
    _ref.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith.tun(enable: !state.tun.enable),
        );
    // 未启动代理时, 只更新配置但不立刻下发到核心。
    // 这样用户在“未启动代理”的状态下切换 TUN 不会触发核心重启
    // 或重新应用配置, 避免出现临时性“无可用节点”/网络异常。
    // 等用户真正点击“启动代理”时, 会通过 updateStatus 中的
    // applyProfileDebounce 统一按照当前配置重新下发到核心。
    if (globalState.isStart) {
      // 仅在代理已运行时才进行实时 TUN 热切换
      updateClashConfigDebounce();
    }
  }

  updateSystemProxy() {
    _ref.read(networkSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            systemProxy: !state.systemProxy,
          ),
        );
  }

  Future<List<Package>> getPackages() async {
    if (_ref.read(isMobileViewProvider)) {
      await Future.delayed(commonDuration);
    }
    if (_ref.read(packagesProvider).isEmpty) {
      _ref.read(packagesProvider.notifier).value =
          await app?.getPackages() ?? [];
    }
    return _ref.read(packagesProvider);
  }

  updateStart() {
    updateStatus(!_ref.read(runTimeProvider.notifier).isStart);
  }

  updateCurrentSelectedMap(String groupName, String proxyName) {
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final SelectedMap selectedMap = Map.from(
        currentProfile.selectedMap,
      )..[groupName] = proxyName;
      _ref.read(profilesProvider.notifier).setProfile(
            currentProfile.copyWith(
              selectedMap: selectedMap,
            ),
          );
    }
  }

  updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile == null) {
      return;
    }
    _ref.read(profilesProvider.notifier).setProfile(
          currentProfile.copyWith(
            unfoldSet: value,
          ),
        );
  }

  changeMode(Mode mode) {
    _ref.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith(mode: mode),
        );
    if (mode == Mode.global) {
      updateCurrentGroupName(GroupName.GLOBAL.name);
    }
    addCheckIpNumDebounce();
    // 如果开启了“切换时关闭连接”, 模式切换后主动断开现有连接,
    // 避免旧连接继续沿用之前的路由策略导致用户感觉模式没有生效
    if (_ref.read(appSettingProvider).closeConnections) {
      clashCore.closeConnections();
    }
    // 切换模式后, 立即把新的模式参数同步到核心, 实现真正的“热切换”
    updateClashConfigDebounce();
  }

  updateAutoLaunch() {
    _ref.read(appSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            autoLaunch: !state.autoLaunch,
          ),
        );
  }

  updateVisible() async {
    final visible = await window?.isVisible;
    if (visible != null && !visible) {
      window?.show();
    } else {
      window?.hide();
    }
  }

  updateMode() {
    _ref.read(patchClashConfigProvider.notifier).updateState(
      (state) {
        final index = Mode.values.indexWhere((item) => item == state.mode);
        if (index == -1) {
          return null;
        }
        final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
        return state.copyWith(
          mode: Mode.values[nextIndex],
        );
      },
    );
  }

  handleAddOrUpdate(WidgetRef ref, [Rule? rule]) async {
    final res = await globalState.showCommonDialog<Rule>(
      child: AddRuleDialog(
        rule: rule,
        snippet: ref.read(
          profileOverrideStateProvider.select(
            (state) => state.snippet!,
          ),
        ),
      ),
    );
    if (res == null) {
      return;
    }
    ref.read(profileOverrideStateProvider.notifier).updateState(
      (state) {
        final model = state.copyWith.overrideData!(
          rule: state.overrideData!.rule.updateRules(
            (rules) {
              final index = rules.indexWhere((item) => item.id == res.id);
              if (index == -1) {
                return List.from([res, ...rules]);
              }
              return List.from(rules)..[index] = res;
            },
          ),
        );
        return model;
      },
    );
  }

  Future<bool> exportLogs() async {
    final logsRaw = _ref.read(logsProvider).list.map(
          (item) => item.toString(),
        );
    final data = await Isolate.run<List<int>>(() async {
      final logsRawString = logsRaw.join("\n");
      return utf8.encode(logsRawString);
    });
    return await picker.saveFile(
          utils.logFile,
          Uint8List.fromList(data),
        ) !=
        null;
  }

  Future<List<int>> backupData() async {
    final homeDirPath = await appPath.homeDirPath;
    final profilesPath = await appPath.profilesPath;
    final configJson = globalState.config.toJson();
    return Isolate.run<List<int>>(() async {
      final archive = Archive();
      archive.add("config.json", configJson);
      await archive.addDirectoryToArchive(profilesPath, homeDirPath);
      final zipEncoder = ZipEncoder();
      return zipEncoder.encode(archive) ?? [];
    });
  }

  updateTray([bool focus = false]) async {
    tray.update(
      trayState: _ref.read(trayStateProvider),
    );
  }

  recoveryData(
    List<int> data,
    RecoveryOption recoveryOption,
  ) async {
    final archive = await Isolate.run<Archive>(() {
      final zipDecoder = ZipDecoder();
      return zipDecoder.decodeBytes(data);
    });
    final homeDirPath = await appPath.homeDirPath;
    final configs =
        archive.files.where((item) => item.name.endsWith(".json")).toList();
    final profiles =
        archive.files.where((item) => !item.name.endsWith(".json"));
    final configIndex =
        configs.indexWhere((config) => config.name == "config.json");
    if (configIndex == -1) throw "invalid backup file";
    final configFile = configs[configIndex];
    var tempConfig = Config.compatibleFromJson(
      json.decode(
        utf8.decode(configFile.content),
      ),
    );
    for (final profile in profiles) {
      final filePath = join(homeDirPath, profile.name);
      final file = File(filePath);
      await file.create(recursive: true);
      await file.writeAsBytes(profile.content);
    }
    final clashConfigIndex =
        configs.indexWhere((config) => config.name == "clashConfig.json");
    if (clashConfigIndex != -1) {
      final clashConfigFile = configs[clashConfigIndex];
      tempConfig = tempConfig.copyWith(
        patchClashConfig: ClashConfig.fromJson(
          json.decode(
            utf8.decode(
              clashConfigFile.content,
            ),
          ),
        ),
      );
    }
    _recovery(
      tempConfig,
      recoveryOption,
    );
  }

  _recovery(Config config, RecoveryOption recoveryOption) {
    final recoveryStrategy = _ref.read(appSettingProvider.select(
      (state) => state.recoveryStrategy,
    ));
    final profiles = config.profiles;
    if (recoveryStrategy == RecoveryStrategy.override) {
      _ref.read(profilesProvider.notifier).value = profiles;
    } else {
      for (final profile in profiles) {
        _ref.read(profilesProvider.notifier).setProfile(
              profile,
            );
      }
    }
    final onlyProfiles = recoveryOption == RecoveryOption.onlyProfiles;
    if (!onlyProfiles) {
      _ref.read(patchClashConfigProvider.notifier).value =
          config.patchClashConfig;
      _ref.read(appSettingProvider.notifier).value = config.appSetting;
      _ref.read(currentProfileIdProvider.notifier).value =
          config.currentProfileId;
      _ref.read(appDAVSettingProvider.notifier).value = config.dav;
      _ref.read(themeSettingProvider.notifier).value = config.themeProps;
      _ref.read(windowSettingProvider.notifier).value = config.windowProps;
      _ref.read(vpnSettingProvider.notifier).value = config.vpnProps;
      _ref.read(proxiesStyleSettingProvider.notifier).value =
          config.proxiesStyle;
      _ref.read(overrideDnsProvider.notifier).value = config.overrideDns;
      _ref.read(networkSettingProvider.notifier).value = config.networkProps;
      _ref.read(hotKeyActionsProvider.notifier).value = config.hotKeyActions;
      _ref.read(scriptStateProvider.notifier).value = config.scriptProps;
    }
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile == null) {
      _ref.read(currentProfileIdProvider.notifier).value = profiles.first.id;
    }
  }
}
