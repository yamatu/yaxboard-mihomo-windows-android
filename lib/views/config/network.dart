import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class VPNItem extends ConsumerWidget {
  const VPNItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final enable =
        ref.watch(vpnSettingProvider.select((state) => state.enable));
    return ListItem.switchItem(
      title: const Text("VPN"),
      subtitle: Text(appLocalizations.vpnEnableDesc),
      delegate: SwitchDelegate(
        value: enable,
        onChanged: (value) async {
          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  enable: value,
                ),
              );
        },
      ),
    );
  }
}

class TUNItem extends ConsumerWidget {
  const TUNItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final enable =
        ref.watch(patchClashConfigProvider.select((state) => state.tun.enable));

    return ListItem.switchItem(
      title: Text(appLocalizations.tun),
      subtitle: Text(appLocalizations.tunDesc),
      delegate: SwitchDelegate(
        value: enable,
        onChanged: (value) async {
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith.tun(
                  enable: value,
                ),
              );
        },
      ),
    );
  }
}

class AllowBypassItem extends ConsumerWidget {
  const AllowBypassItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final allowBypass =
        ref.watch(vpnSettingProvider.select((state) => state.allowBypass));
    return ListItem.switchItem(
      title: Text(appLocalizations.allowBypass),
      subtitle: Text(appLocalizations.allowBypassDesc),
      delegate: SwitchDelegate(
        value: allowBypass,
        onChanged: (bool value) async {
          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  allowBypass: value,
                ),
              );
        },
      ),
    );
  }
}

class VpnSystemProxyItem extends ConsumerWidget {
  const VpnSystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    // 统一“系统代理”开关的语义：
    // - 桌面端：由 networkSettingProvider.systemProxy 控制（对应系统代理插件）
    // - Android：由 vpnSettingProvider.systemProxy 控制（对应 VPN 相关逻辑）
    final systemProxy = system.isDesktop
        ? ref.watch(networkSettingProvider.select((state) => state.systemProxy))
        : ref.watch(vpnSettingProvider.select((state) => state.systemProxy));
    return ListItem.switchItem(
      title: Text(appLocalizations.systemProxy),
      subtitle: Text(appLocalizations.systemProxyDesc),
      delegate: SwitchDelegate(
        value: systemProxy,
        onChanged: (bool value) async {
          if (system.isDesktop) {
            // 桌面端只需要控制 networkProps.systemProxy，即可触发 ProxyManager 调用 StartProxy。
            ref.read(networkSettingProvider.notifier).updateState(
                  (state) => state.copyWith(
                    systemProxy: value,
                  ),
                );
            // 同步写一份到 vpnProps，避免配置文件里出现“两个开关值不一致”导致用户困惑。
            ref.read(vpnSettingProvider.notifier).updateState(
                  (state) => state.copyWith(
                    systemProxy: value,
                  ),
                );
            return;
          }

          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  systemProxy: value,
                ),
              );
        },
      ),
    );
  }
}

class SystemProxyItem extends ConsumerWidget {
  const SystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final systemProxy =
        ref.watch(networkSettingProvider.select((state) => state.systemProxy));

    return ListItem.switchItem(
      title: Text(appLocalizations.systemProxy),
      subtitle: Text(appLocalizations.systemProxyDesc),
      delegate: SwitchDelegate(
        value: systemProxy,
        onChanged: (bool value) async {
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  systemProxy: value,
                ),
              );
        },
      ),
    );
  }
}

class Ipv6Item extends ConsumerWidget {
  const Ipv6Item({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final ipv6 = ref.watch(vpnSettingProvider.select((state) => state.ipv6));
    return ListItem.switchItem(
      title: const Text("IPv6"),
      subtitle: Text(appLocalizations.ipv6InboundDesc),
      delegate: SwitchDelegate(
        value: ipv6,
        onChanged: (bool value) async {
          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  ipv6: value,
                ),
              );
        },
      ),
    );
  }
}

class AutoSetSystemDnsItem extends ConsumerWidget {
  const AutoSetSystemDnsItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final autoSetSystemDns = ref.watch(
        networkSettingProvider.select((state) => state.autoSetSystemDns));
    return ListItem.switchItem(
      title: Text(appLocalizations.autoSetSystemDns),
      delegate: SwitchDelegate(
        value: autoSetSystemDns,
        onChanged: (bool value) async {
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  autoSetSystemDns: value,
                ),
              );
        },
      ),
    );
  }
}

class AirportProxyItem extends ConsumerWidget {
  const AirportProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final proxyBackendTraffic = ref.watch(
      networkSettingProvider.select((state) => state.proxyBackendTraffic),
    );
    return ListItem.switchItem(
      title: const Text('机场代理'),
      subtitle: const Text('控制机场面板、订阅和客服等后端请求是否通过本地代理'),
      delegate: SwitchDelegate(
        value: proxyBackendTraffic,
        onChanged: (bool value) async {
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  proxyBackendTraffic: value,
                ),
              );
        },
      ),
    );
  }
}

class ClientEchItem extends ConsumerWidget {
  const ClientEchItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final clientEch =
        ref.watch(networkSettingProvider.select((state) => state.clientEch));
    return ListItem.switchItem(
      title: const Text('ECH'),
      subtitle: const Text(
        'Use subscription ECH config. DNS ECH falls back to Cloudflare + AliDNS when the node only provides partial ECH fields.',
      ),
      delegate: SwitchDelegate(
        value: clientEch,
        onChanged: (bool value) async {
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  clientEch: value,
                ),
              );
        },
      ),
    );
  }
}

class ClientEchForceQueryItem extends ConsumerWidget {
  const ClientEchForceQueryItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final forceQuery = ref.watch(
      networkSettingProvider.select((state) => state.clientEchForceQuery),
    );
    return ListItem<String>.options(
      title: const Text('ECH Force Query'),
      subtitle: Text(forceQuery.isEmpty ? 'off' : forceQuery),
      delegate: OptionsDelegate<String>(
        title: 'ECH Force Query',
        options: const ['full', 'off'],
        textBuilder: (value) => value,
        value: forceQuery.isEmpty ? 'off' : forceQuery,
        onChanged: (value) {
          if (value == null) {
            return;
          }
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  clientEchForceQuery: value == 'off' ? '' : value,
                ),
              );
        },
      ),
    );
  }
}

class ClientEchQueryServerNameItem extends ConsumerWidget {
  const ClientEchQueryServerNameItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final queryServerName = ref.watch(
      networkSettingProvider.select((state) => state.clientEchQueryServerName),
    );
    return ListItem.input(
      title: const Text('ECH Query Server Name'),
      subtitle: Text(queryServerName.isEmpty ? 'Not set' : queryServerName),
      delegate: InputDelegate(
        title: 'ECH Query Server Name',
        value: queryServerName,
        resetValue: defaultClientEchQueryServerName,
        onChanged: (value) {
          if (value == null) {
            return;
          }
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  clientEchQueryServerName: value.trim(),
                ),
              );
        },
      ),
    );
  }
}

class ClientEchConfigListItem extends ConsumerWidget {
  const ClientEchConfigListItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final configList = ref.watch(
      networkSettingProvider.select((state) => state.clientEchConfigList),
    );
    return ListItem.input(
      title: const Text('ECH Config List'),
      subtitle: Text(configList.isEmpty ? 'Not set' : configList),
      delegate: InputDelegate(
        title: 'ECH Config List',
        value: configList,
        resetValue: defaultClientEchConfigList,
        onChanged: (value) {
          if (value == null) {
            return;
          }
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  clientEchConfigList: value.trim(),
                ),
              );
        },
      ),
    );
  }
}

class TunStackItem extends ConsumerWidget {
  const TunStackItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final stack =
        ref.watch(patchClashConfigProvider.select((state) => state.tun.stack));

    return ListItem.options(
      title: Text(appLocalizations.stackMode),
      subtitle: Text(stack.name),
      delegate: OptionsDelegate<TunStack>(
        value: stack,
        options: TunStack.values,
        textBuilder: (value) => value.name,
        onChanged: (value) {
          if (value == null) {
            return;
          }
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith.tun(
                  stack: value,
                ),
              );
        },
        title: appLocalizations.stackMode,
      ),
    );
  }
}

class BypassDomainItem extends StatelessWidget {
  const BypassDomainItem({super.key});

  _initActions(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      context.commonScaffoldState?.actions = [
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () async {
            final res = await globalState.showMessage(
              title: appLocalizations.reset,
              message: TextSpan(
                text: appLocalizations.resetTip,
              ),
            );
            if (res != true) {
              return;
            }
            ref.read(networkSettingProvider.notifier).updateState(
                  (state) => state.copyWith(
                    bypassDomain: defaultBypassDomain,
                  ),
                );
          },
          child: const Icon(
            CupertinoIcons.arrow_counterclockwise,
          ),
        )
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      title: Text(appLocalizations.bypassDomain),
      subtitle: Text(appLocalizations.bypassDomainDesc),
      delegate: OpenDelegate(
        blur: false,
        title: appLocalizations.bypassDomain,
        widget: Consumer(
          builder: (_, ref, __) {
            _initActions(context, ref);
            final bypassDomain = ref.watch(
                networkSettingProvider.select((state) => state.bypassDomain));
            return ListInputPage(
              title: appLocalizations.bypassDomain,
              items: bypassDomain,
              titleBuilder: (item) => Text(item),
              onChange: (items) {
                ref.read(networkSettingProvider.notifier).updateState(
                      (state) => state.copyWith(
                        bypassDomain: List.from(items),
                      ),
                    );
              },
            );
          },
        ),
      ),
    );
  }
}

class CustomDirectDomainsItem extends StatelessWidget {
  const CustomDirectDomainsItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      title: const Text('自定义直连域名'),
      subtitle: const Text('这里添加的域名会自动写入运行配置，并优先按 DIRECT 分流'),
      delegate: OpenDelegate(
        blur: false,
        title: '自定义直连域名',
        widget: Consumer(
          builder: (_, ref, __) {
            final items = ref.watch(
              networkSettingProvider.select(
                (state) => state.customDirectDomains,
              ),
            );
            return ListInputPage(
              title: '自定义直连域名',
              items: items,
              titleBuilder: (item) => Text(item),
              onChange: (values) {
                ref.read(networkSettingProvider.notifier).updateState(
                      (state) => state.copyWith(
                        customDirectDomains: List<String>.from(values),
                      ),
                    );
              },
            );
          },
        ),
      ),
    );
  }
}

class CustomProxyDomainsItem extends StatelessWidget {
  const CustomProxyDomainsItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      title: const Text('自定义代理域名'),
      subtitle: const Text('这里添加的域名会自动写入运行配置，并优先走当前代理分组'),
      delegate: OpenDelegate(
        blur: false,
        title: '自定义代理域名',
        widget: Consumer(
          builder: (_, ref, __) {
            final items = ref.watch(
              networkSettingProvider.select(
                (state) => state.customProxyDomains,
              ),
            );
            return ListInputPage(
              title: '自定义代理域名',
              items: items,
              titleBuilder: (item) => Text(item),
              onChange: (values) {
                ref.read(networkSettingProvider.notifier).updateState(
                      (state) => state.copyWith(
                        customProxyDomains: List<String>.from(values),
                      ),
                    );
              },
            );
          },
        ),
      ),
    );
  }
}

class RouteModeItem extends ConsumerWidget {
  const RouteModeItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final routeMode =
        ref.watch(networkSettingProvider.select((state) => state.routeMode));
    return ListItem<RouteMode>.options(
      title: Text(appLocalizations.routeMode),
      subtitle: Text(Intl.message("routeMode_${routeMode.name}")),
      delegate: OptionsDelegate<RouteMode>(
        title: appLocalizations.routeMode,
        options: RouteMode.values,
        onChanged: (RouteMode? value) {
          if (value == null) {
            return;
          }
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  routeMode: value,
                ),
              );
        },
        textBuilder: (routeMode) => Intl.message(
          "routeMode_${routeMode.name}",
        ),
        value: routeMode,
      ),
    );
  }
}

class RouteAddressItem extends ConsumerWidget {
  const RouteAddressItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final bypassPrivate = ref.watch(networkSettingProvider
        .select((state) => state.routeMode == RouteMode.bypassPrivate));
    if (bypassPrivate) {
      return Container();
    }
    return ListItem.open(
      title: Text(appLocalizations.routeAddress),
      subtitle: Text(appLocalizations.routeAddressDesc),
      delegate: OpenDelegate(
        blur: false,
        maxWidth: 360,
        title: appLocalizations.routeAddress,
        widget: Consumer(
          builder: (_, ref, __) {
            final routeAddress = ref.watch(
              patchClashConfigProvider.select(
                (state) => state.tun.routeAddress,
              ),
            );
            return ListInputPage(
              title: appLocalizations.routeAddress,
              items: routeAddress,
              titleBuilder: (item) => Text(item),
              onChange: (items) {
                ref.read(patchClashConfigProvider.notifier).updateState(
                      (state) => state.copyWith.tun(
                        routeAddress: List.from(items),
                      ),
                    );
              },
            );
          },
        ),
      ),
    );
  }
}

final networkItems = [
  if (Platform.isAndroid) const VPNItem(),
  if (Platform.isAndroid)
    ...generateSection(
      title: "VPN",
      items: [
        const VpnSystemProxyItem(),
        const BypassDomainItem(),
        const CustomDirectDomainsItem(),
        const CustomProxyDomainsItem(),
        const AllowBypassItem(),
        const Ipv6Item(),
        const AirportProxyItem(),
      ],
    ),
  if (system.isDesktop)
    ...generateSection(
      title: appLocalizations.system,
      items: [
        SystemProxyItem(),
        BypassDomainItem(),
        const CustomDirectDomainsItem(),
        const CustomProxyDomainsItem(),
        const AirportProxyItem(),
      ],
    ),
  ...generateSection(
    title: appLocalizations.options,
    items: [
      if (system.isDesktop) const TUNItem(),
      if (Platform.isMacOS) const AutoSetSystemDnsItem(),
      const ClientEchItem(),
      const ClientEchForceQueryItem(),
      const ClientEchQueryServerNameItem(),
      const ClientEchConfigListItem(),
      const TunStackItem(),
      if (!system.isDesktop) ...[
        const RouteModeItem(),
        const RouteAddressItem(),
      ]
    ],
  ),
];

class NetworkListView extends ConsumerWidget {
  const NetworkListView({super.key});

  _initActions(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      context.commonScaffoldState?.actions = [
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () async {
            final res = await globalState.showMessage(
              title: appLocalizations.reset,
              message: TextSpan(
                text: appLocalizations.resetTip,
              ),
            );
            if (res != true) {
              return;
            }
            ref.read(vpnSettingProvider.notifier).updateState(
                  (state) => defaultVpnProps.copyWith(
                    accessControl: state.accessControl,
                  ),
                );
            ref.read(patchClashConfigProvider.notifier).updateState(
                  (state) => state.copyWith(
                    tun: defaultTun,
                  ),
                );
          },
          child: const Icon(
            CupertinoIcons.arrow_counterclockwise,
          ),
        )
      ];
    });
  }

  @override
  Widget build(BuildContext context, ref) {
    _initActions(context, ref);
    return generateListView(
      networkItems,
    );
  }
}
