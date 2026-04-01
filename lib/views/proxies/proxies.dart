import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/views/proxies/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'setting.dart';
import 'tab.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key});

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> with PageMixin {
  final GlobalKey<ProxiesTabViewState> _proxiesTabKey = GlobalKey();
  bool _hasProviders = false;
  bool _isTab = false;

  @override
  get actions => [
        if (_isTab)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              _proxiesTabKey.currentState?.scrollToGroupSelected();
            },
            child: Icon(
              CupertinoIcons.scope,
              size: 22,
            ),
          ),
        CommonPopupBox(
          targetBuilder: (open) {
            return CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                open(
                  offset: Offset(0, 20),
                );
              },
              child: Icon(
                CupertinoIcons.ellipsis_vertical,
              ),
            );
          },
          popup: CommonPopupMenu(
            items: [
              PopupMenuItemData(
                icon: CupertinoIcons.slider_horizontal_3,
                label: appLocalizations.settings,
                onPressed: () {
                  showSheet(
                    context: context,
                    props: SheetProps(
                      isScrollControlled: true,
                    ),
                    builder: (_, type) {
                      return AdaptiveSheetScaffold(
                        type: type,
                        body: const ProxiesSetting(),
                        title: appLocalizations.settings,
                      );
                    },
                  );
                },
              ),
              if (_hasProviders)
                PopupMenuItemData(
                  icon: CupertinoIcons.chart_bar,
                  label: appLocalizations.providers,
                  onPressed: () {
                    showExtend(
                      context,
                      builder: (_, type) {
                        return ProvidersView(
                          type: type,
                        );
                      },
                    );
                  },
                ),
              if (!_isTab)
                PopupMenuItemData(
                  icon: CupertinoIcons.paintbrush,
                  label: appLocalizations.iconConfiguration,
                  onPressed: () {
                    showExtend(
                      context,
                      builder: (_, type) {
                        return AdaptiveSheetScaffold(
                          type: type,
                          body: const _IconConfigView(),
                          title: appLocalizations.iconConfiguration,
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        )
      ];

  @override
  get onSearch => (value) {
        ref.read(proxiesQueryProvider.notifier).value = value;
      };

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(proxiesQueryProvider.notifier).value = "";
      }
    });
  }

  @override
  get floatingActionButton => null;

  Future<void> _delayTestAllNodes() async {
    final groups = globalState.appController.getCurrentGroups();
    if (groups.isEmpty) {
      return;
    }
    for (final group in groups) {
      await delayTest(group.all, group.testUrl);
    }
  }

  @override
  void initState() {
    [
      if (_hasProviders)
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            showExtend(
              context,
              builder: (_, type) {
                return ProvidersView(
                  type: type,
                );
              },
            );
          },
          child: const Icon(
            CupertinoIcons.chart_bar,
          ),
        ),
      _isTab
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                _proxiesTabKey.currentState?.scrollToGroupSelected();
              },
              child: const Icon(
                CupertinoIcons.scope,
              ),
            )
          : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                showExtend(
                  context,
                  builder: (_, type) {
                    return AdaptiveSheetScaffold(
                      type: type,
                      body: const _IconConfigView(),
                      title: appLocalizations.iconConfiguration,
                    );
                  },
                );
              },
              child: const Icon(
                CupertinoIcons.paintbrush,
              ),
            ),
      CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () {
          showSheet(
            context: context,
            props: SheetProps(
              isScrollControlled: true,
            ),
            builder: (_, type) {
              return AdaptiveSheetScaffold(
                type: type,
                body: const ProxiesSetting(),
                title: appLocalizations.settings,
              );
            },
          );
        },
        child: const Icon(
          CupertinoIcons.slider_horizontal_3,
        ),
      )
    ];
    ref.listenManual(
      proxiesActionsStateProvider,
      fireImmediately: true,
      (prev, next) {
        if (prev == next) {
          return;
        }
        if (next.pageLabel == PageLabel.proxies) {
          _hasProviders = next.hasProviders;
          _isTab = next.type == ProxiesType.tab;
          initPageState();
          return;
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(proxiesQueryProvider.notifier).value = "";
            }
          });
        }
      },
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final proxiesType = ref.watch(
      proxiesStyleSettingProvider.select(
        (state) => state.type,
      ),
    );
    final body = switch (proxiesType) {
      ProxiesType.tab => ProxiesTabView(
          key: _proxiesTabKey,
        ),
      ProxiesType.list => const ProxiesListView(),
    };
    return FadeThroughBox(
      child: Stack(
        key: ValueKey(proxiesType),
        children: [
          Positioned.fill(child: body),
          Positioned(
            right: 16,
            bottom: 16,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (_, value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: DelayTestButton(
                onClick: _delayTestAllNodes,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconConfigView extends ConsumerWidget {
  const _IconConfigView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconMap = ref.watch(proxiesStyleSettingProvider.select(
      (state) => state.iconMap,
    ));
    return MapInputPage(
      title: appLocalizations.iconConfiguration,
      map: iconMap,
      keyLabel: appLocalizations.regExp,
      valueLabel: appLocalizations.icon,
      titleBuilder: (item) => Text(item.key),
      leadingBuilder: (item) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: CommonTargetIcon(
          src: item.value,
          size: 42,
        ),
      ),
      subtitleBuilder: (item) => Text(
        item.value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onChange: (value) {
        ref.read(proxiesStyleSettingProvider.notifier).updateState(
              (state) => state.copyWith(
                iconMap: value,
              ),
            );
      },
    );
  }
}
