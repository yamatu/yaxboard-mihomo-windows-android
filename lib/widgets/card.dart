import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/widgets/fade_box.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'text.dart';

class Info {
  final String label;
  final IconData? iconData;

  const Info({
    required this.label,
    this.iconData,
  });
}

class InfoHeader extends StatelessWidget {
  final Info info;
  final List<Widget> actions;
  final EdgeInsetsGeometry? padding;

  const InfoHeader({
    super.key,
    required this.info,
    this.padding,
    List<Widget>? actions,
  }) : actions = actions ?? const [];

  @override
  Widget build(BuildContext context) {
    final secondaryLabel = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return Padding(
      padding: padding ?? baseInfoEdgeInsets,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 1,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                if (info.iconData != null) ...[
                  Icon(
                    info.iconData,
                    color: secondaryLabel,
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                ],
                Flexible(
                  flex: 1,
                  child: TooltipText(
                    text: Text(
                      info.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: secondaryLabel,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 8,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ...actions,
            ],
          ),
        ],
      ),
    );
  }
}

class CommonCard extends StatelessWidget {
  const CommonCard({
    super.key,
    bool? isSelected,
    this.type = CommonCardType.plain,
    this.onPressed,
    this.selectWidget,
    this.radius = 12,
    required this.child,
    this.padding,
    this.enterAnimated = false,
    this.info,
  }) : isSelected = isSelected ?? false;

  final bool enterAnimated;
  final bool isSelected;
  final void Function()? onPressed;
  final Widget? selectWidget;
  final Widget child;
  final EdgeInsets? padding;
  final Info? info;
  final CommonCardType type;
  final double radius;

  // final WidgetStateProperty<Color?>? backgroundColor;
  // final WidgetStateProperty<BorderSide?>? borderSide;

  @override
  Widget build(BuildContext context) {
    var childWidget = child;

    if (info != null) {
      childWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfoHeader(
            padding: baseInfoEdgeInsets.copyWith(
              bottom: 0,
            ),
            info: info!,
          ),
          Flexible(
            flex: 1,
            child: child,
          ),
        ],
      );
    }

    if (selectWidget != null && isSelected) {
      final List<Widget> children = [];
      children.add(childWidget);
      children.add(
        Positioned.fill(
          child: selectWidget!,
        ),
      );
      childWidget = Stack(
        children: children,
      );
    }

    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = type == CommonCardType.filled
        ? (isSelected
            ? CupertinoTheme.of(context).primaryColor.withOpacity(0.12)
            : CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemGroupedBackground, context))
        : (isSelected
            ? CupertinoTheme.of(context).primaryColor.withOpacity(0.10)
            : CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context));

    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(radius),
          border: type != CommonCardType.filled
              ? Border.all(
                  color: isSelected
                      ? CupertinoTheme.of(context).primaryColor
                      : CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
                  width: 0.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.transparent : const Color(0x0D000000),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: childWidget,
      ),
    );

    return switch (enterAnimated) {
      true => FadeScaleEnterBox(
          child: card,
        ),
      false => card,
    };
  }
}

class SelectIcon extends StatelessWidget {
  const SelectIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).primaryColor.withOpacity(0.85),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        CupertinoIcons.check_mark,
        size: 16,
        color: CupertinoColors.white,
      ),
    );
  }
}

class SettingsBlock extends StatelessWidget {
  final String title;
  final List<Widget> settings;

  const SettingsBlock({
    super.key,
    required this.title,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(8),
      child: Column(
        children: [
          InfoHeader(
            info: Info(
              label: title,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemGroupedBackground,
                context,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: settings,
            ),
          ),
        ],
      ),
    );
  }
}
