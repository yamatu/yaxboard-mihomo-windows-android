import 'package:flutter/cupertino.dart';

class AppCupertinoColors {
  // Grouped list backgrounds
  static const Color groupedBackground = CupertinoColors.systemGroupedBackground;
  static const Color secondaryGroupedBackground = CupertinoColors.secondarySystemGroupedBackground;
  static const Color tertiaryGroupedBackground = CupertinoColors.tertiarySystemGroupedBackground;

  // Separator
  static const Color separator = CupertinoColors.separator;
  static const Color opaqueSeparator = CupertinoColors.opaqueSeparator;

  // System fills
  static const Color systemFill = CupertinoColors.systemFill;
  static const Color secondarySystemFill = CupertinoColors.secondarySystemFill;
  static const Color tertiarySystemFill = CupertinoColors.tertiarySystemFill;
  static const Color quaternarySystemFill = CupertinoColors.quaternarySystemFill;

  // Labels
  static const Color label = CupertinoColors.label;
  static const Color secondaryLabel = CupertinoColors.secondaryLabel;
  static const Color tertiaryLabel = CupertinoColors.tertiaryLabel;
  static const Color quaternaryLabel = CupertinoColors.quaternaryLabel;

  // System backgrounds
  static const Color systemBackground = CupertinoColors.systemBackground;
  static const Color secondarySystemBackground = CupertinoColors.secondarySystemBackground;
  static const Color tertiarySystemBackground = CupertinoColors.tertiarySystemBackground;

  // Navigation bar background (semi-transparent for blur)
  static Color navBarBackground(Brightness brightness) {
    return brightness == Brightness.dark
        ? const Color(0xE6161616) // dark semi-transparent
        : const Color(0xF0F9F9F9); // light semi-transparent
  }

  // Tab bar background
  static Color tabBarBackground(Brightness brightness) {
    return brightness == Brightness.dark
        ? const Color(0xF01C1C1E)
        : const Color(0xF0F8F8F8);
  }
}
