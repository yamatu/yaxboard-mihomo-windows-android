import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';

class ThemeDialog extends ConsumerWidget {
  const ThemeDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentThemeMode = ref.read(themeSettingProvider.select((state) => state.themeMode));

    return CupertinoAlertDialog(
      title: Text(appLocalizations.selectTheme),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _buildThemeOption(
            context: context,
            icon: CupertinoIcons.circle_lefthalf_fill,
            label: appLocalizations.auto,
            value: ThemeMode.system,
            groupValue: currentThemeMode,
            onSelected: (value) {
              ref.read(themeSettingProvider.notifier).updateState(
                (state) => state.copyWith(themeMode: value),
              );
              Navigator.of(context).pop();
            },
          ),
          _buildThemeOption(
            context: context,
            icon: CupertinoIcons.sun_max_fill,
            label: appLocalizations.light,
            value: ThemeMode.light,
            groupValue: currentThemeMode,
            onSelected: (value) {
              ref.read(themeSettingProvider.notifier).updateState(
                (state) => state.copyWith(themeMode: value),
              );
              Navigator.of(context).pop();
            },
          ),
          _buildThemeOption(
            context: context,
            icon: CupertinoIcons.moon_fill,
            label: appLocalizations.dark,
            value: ThemeMode.dark,
            groupValue: currentThemeMode,
            onSelected: (value) {
              ref.read(themeSettingProvider.notifier).updateState(
                (state) => state.copyWith(themeMode: value),
              );
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocalizations.cancel),
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required ThemeMode value,
    required ThemeMode groupValue,
    required ValueChanged<ThemeMode> onSelected,
  }) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? CupertinoTheme.of(context).primaryColor.withValues(alpha: 0.12)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? CupertinoTheme.of(context).primaryColor
                  : CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                ),
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark,
                size: 18,
                color: CupertinoTheme.of(context).primaryColor,
              ),
          ],
        ),
      ),
    );
  }
}
