import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/xboard/features/invite/widgets/user_menu_widget.dart';
import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/features/update_check/providers/update_check_provider.dart';
import 'package:fl_clash/xboard/features/update_check/widgets/update_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopNavigationRail extends ConsumerWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;

  const DesktopNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        border: Border(
          right: BorderSide(
            color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Expanded(
            child: _buildNavigationItems(context, colorScheme),
          ),
          _buildUpdateButton(context, ref, colorScheme),
          _buildBottomActions(colorScheme),
        ],
      ),
    );
  }

  Widget _buildUpdateButton(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    final updateState = ref.watch(updateCheckProvider);
    final hasUpdate = updateState.hasUpdate;
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final secondaryLabel = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final notifier = ref.read(updateCheckProvider.notifier);
          await notifier.checkForUpdates();
          if (!context.mounted) return;
          final state = ref.read(updateCheckProvider);
          if (state.hasUpdate) {
            showDialog(
              context: context,
              barrierDismissible: !state.forceUpdate,
              builder: (_) => const UpdateDialog(),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error ?? '当前已是最新版本'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    CupertinoIcons.arrow_down_circle,
                    size: 22,
                    color: hasUpdate
                        ? primaryColor
                        : secondaryLabel,
                  ),
                  if (hasUpdate)
                    Positioned(
                      top: -3,
                      right: -6,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondarySystemGroupedBackground,
                              context,
                            ),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '更新',
                style: TextStyle(
                  fontSize: 10,
                  color: hasUpdate
                      ? primaryColor
                      : secondaryLabel,
                  fontWeight: hasUpdate ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(
      width: 40,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            CupertinoDynamicColor.withBrightness(
              color: CupertinoColors.separator.color,
              darkColor: CupertinoColors.separator.darkColor,
            ).withOpacity(0.3),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationItems(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final appLocalizations = AppLocalizations.of(context);
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final secondaryLabel = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    final items = [
      _NavItem(icon: CupertinoIcons.house, activeIcon: CupertinoIcons.house_fill, label: appLocalizations.xboardHome),
      _NavItem(icon: CupertinoIcons.bag, activeIcon: CupertinoIcons.bag_fill, label: appLocalizations.xboardPlans),
      _NavItem(icon: CupertinoIcons.person_2, activeIcon: CupertinoIcons.person_2_fill, label: appLocalizations.invite),
      _NavItem(icon: CupertinoIcons.antenna_radiowaves_left_right, activeIcon: CupertinoIcons.antenna_radiowaves_left_right, label: '连接'),
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onDestinationSelected(i),
            child: Container(
              width: 64,
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selectedIndex == i ? primaryColor.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selectedIndex == i ? items[i].activeIcon : items[i].icon,
                    size: 24,
                    color: selectedIndex == i ? primaryColor : secondaryLabel,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i].label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selectedIndex == i ? FontWeight.w600 : FontWeight.normal,
                      color: selectedIndex == i ? primaryColor : secondaryLabel,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomActions(ColorScheme colorScheme) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildDivider(colorScheme),
        const SizedBox(height: 16),
        const UserMenuWidget(),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
