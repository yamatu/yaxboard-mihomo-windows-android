import 'package:fl_clash/common/common.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CommonTheme {
  final BuildContext context;
  final Map<String, Color> _colorMap;
  final double textScaleFactor;

  CommonTheme.of(
    this.context,
    this.textScaleFactor,
  ) : _colorMap = {};

  Color get darkenSecondaryContainer {
    return _colorMap.updateCacheValue(
      "darkenSecondaryContainer",
      () => context.colorScheme.secondaryContainer
          .blendDarken(context, factor: 0.1),
    );
  }

  Color get darkenSecondaryContainerLighter {
    return _colorMap.updateCacheValue(
      "darkenSecondaryContainerLighter",
      () => context.colorScheme.secondaryContainer
          .blendDarken(context, factor: 0.1)
          .opacity60,
    );
  }

  Color get darken2SecondaryContainer {
    return _colorMap.updateCacheValue(
      "darken2SecondaryContainer",
      () => context.colorScheme.secondaryContainer
          .blendDarken(context, factor: 0.2),
    );
  }

  Color get darken3PrimaryContainer {
    return _colorMap.updateCacheValue(
      "darken3PrimaryContainer",
      () => context.colorScheme.primaryContainer
          .blendDarken(context, factor: 0.3),
    );
  }

  // Cupertino grouped background colors
  Color get groupedBackground {
    return CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
  }

  Color get secondaryGroupedBackground {
    return CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
  }

  Color get iosSeparator {
    return CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
  }
}
