import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/views/config/network.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TUNButton extends StatelessWidget {
  const TUNButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {
          showSheet(
            context: context,
            builder: (_, type) {
              return AdaptiveSheetScaffold(
                type: type,
                body: generateListView(
                  generateSection(
                    items: [
                      if (system.isDesktop) const TUNItem(),
                      if (Platform.isMacOS) const AutoSetSystemDnsItem(),
                      const TunStackItem(),
                    ],
                  ),
                ),
                title: appLocalizations.tun,
              );
            },
          );
        },
        info: Info(
          label: appLocalizations.tun,
          iconData: CupertinoIcons.chart_bar_alt_fill,
        ),
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 4,
            bottom: 8,
            right: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: TooltipText(
                  text: Text(
                    appLocalizations.options,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ),
              ),
              Consumer(
                builder: (_, ref, __) {
                  final enable = ref.watch(patchClashConfigProvider
                      .select((state) => state.tun.enable));
                  return CupertinoSwitch(
                    value: enable,
                    onChanged: (value) {
                      ref.read(patchClashConfigProvider.notifier).updateState(
                            (state) => state.copyWith.tun(
                              enable: value,
                            ),
                          );
                    },
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}

class SystemProxyButton extends StatelessWidget {
  const SystemProxyButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {
          showSheet(
            context: context,
            builder: (_, type) {
              return AdaptiveSheetScaffold(
                type: type,
                body: generateListView(
                  generateSection(
                    items: [
                      SystemProxyItem(),
                      BypassDomainItem(),
                    ],
                  ),
                ),
                title: appLocalizations.systemProxy,
              );
            },
          );
        },
        info: Info(
          label: appLocalizations.systemProxy,
          iconData: CupertinoIcons.shuffle,
        ),
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 4,
            bottom: 8,
            right: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: TooltipText(
                  text: Text(
                    appLocalizations.options,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ),
              ),
              Consumer(
                builder: (_, ref, __) {
                  final systemProxy = ref.watch(networkSettingProvider
                      .select((state) => state.systemProxy));
                  return CupertinoSwitch(
                    value: systemProxy,
                    onChanged: (value) {
                      ref.read(networkSettingProvider.notifier).updateState(
                            (state) => state.copyWith(
                              systemProxy: value,
                            ),
                          );
                    },
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}

class VpnButton extends StatelessWidget {
  const VpnButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {
          showSheet(
            context: context,
            builder: (_, type) {
              return AdaptiveSheetScaffold(
                type: type,
                body: generateListView(
                  generateSection(
                    items: [
                      const VPNItem(),
                      const VpnSystemProxyItem(),
                      const TunStackItem(),
                    ],
                  ),
                ),
                title: "VPN",
              );
            },
          );
        },
        info: Info(
          label: "VPN",
          iconData: CupertinoIcons.chart_bar_alt_fill,
        ),
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 4,
            bottom: 8,
            right: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: TooltipText(
                  text: Text(
                    appLocalizations.options,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ),
              ),
              Consumer(
                builder: (_, ref, __) {
                  final enable = ref.watch(
                    vpnSettingProvider.select(
                      (state) => state.enable,
                    ),
                  );
                  return CupertinoSwitch(
                    value: enable,
                    onChanged: (value) {
                      ref.read(vpnSettingProvider.notifier).updateState(
                            (state) => state.copyWith(
                              enable: value,
                            ),
                          );
                    },
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}

class IPv6Button extends StatelessWidget {
  const IPv6Button({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {
          showSheet(
            context: context,
            builder: (_, type) {
              return AdaptiveSheetScaffold(
                type: type,
                body: generateListView(
                  generateSection(
                    items: [
                      const _IPv6ConfigItem(),
                    ],
                  ),
                ),
                title: "IPv6",
              );
            },
          );
        },
        info: const Info(
          label: "IPv6",
          iconData: CupertinoIcons.globe,
        ),
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 4,
            bottom: 8,
            right: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: TooltipText(
                  text: Text(
                    appLocalizations.options,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ),
              ),
              Consumer(
                builder: (_, ref, __) {
                  final ipv6 = system.isDesktop
                      ? ref.watch(
                          patchClashConfigProvider.select((state) => state.ipv6),
                        )
                      : ref.watch(
                          patchClashConfigProvider.select(
                            (state) => state.ipv6,
                          ),
                        ) &&
                          ref.watch(
                            vpnSettingProvider.select((state) => state.ipv6),
                          );
                  return CupertinoSwitch(
                    value: ipv6,
                    onChanged: (value) {
                      _updateIpv6Setting(ref, value);
                    },
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}

void _updateIpv6Setting(WidgetRef ref, bool value) {
  ref.read(patchClashConfigProvider.notifier).updateState(
        (state) => state.copyWith(
          ipv6: value,
        ),
      );
  if (!system.isDesktop) {
    ref.read(vpnSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            ipv6: value,
          ),
        );
  }
}

class _IPv6ConfigItem extends ConsumerWidget {
  const _IPv6ConfigItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ipv6 = system.isDesktop
        ? ref.watch(
            patchClashConfigProvider.select((state) => state.ipv6),
          )
        : ref.watch(
            patchClashConfigProvider.select((state) => state.ipv6),
          ) &&
            ref.watch(
              vpnSettingProvider.select((state) => state.ipv6),
            );
    final subtitle = system.isDesktop
        ? appLocalizations.ipv6Desc
        : "${appLocalizations.ipv6Desc}\n${appLocalizations.ipv6InboundDesc}";
    return ListItem.switchItem(
      title: const Text("IPv6"),
      subtitle: Text(subtitle),
      delegate: SwitchDelegate(
        value: ipv6,
        onChanged: (value) async {
          _updateIpv6Setting(ref, value);
        },
      ),
    );
  }
}
