import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_clash/l10n/l10n.dart';

/// 移动端底部导航栏 - iOS CupertinoTabBar 风格
class MobileNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;

  const MobileNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: CupertinoTabBar(
          currentIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onTap: onDestinationSelected,
          backgroundColor: CupertinoTheme.of(context).barBackgroundColor.withOpacity(0.85),
          border: Border(
            top: BorderSide(
              color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
              width: 0.5,
            ),
          ),
          items: [
            BottomNavigationBarItem(
              icon: const Icon(CupertinoIcons.house, size: 22),
              activeIcon: const Icon(CupertinoIcons.house_fill, size: 22),
              label: appLocalizations.xboardHome,
            ),
            BottomNavigationBarItem(
              icon: const Icon(CupertinoIcons.person_2, size: 22),
              activeIcon: const Icon(CupertinoIcons.person_2_fill, size: 22),
              label: appLocalizations.invite,
            ),
          ],
        ),
      ),
    );
  }
}
