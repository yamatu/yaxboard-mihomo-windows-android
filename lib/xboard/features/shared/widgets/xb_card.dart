import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class XBCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool isSelected;
  final double? elevation;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  const XBCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.isSelected = false,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
  });
  @override
  Widget build(BuildContext context) {
    final defaultBorderRadius = BorderRadius.circular(12);
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final cardBg = backgroundColor ??
        (isSelected
            ? primaryColor.withValues(alpha: 0.12)
            : CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemGroupedBackground, context));
    final borderSideColor = isSelected
        ? primaryColor
        : CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
    final resolvedBorderRadius = borderRadius ?? defaultBorderRadius;

    return Container(
      margin: margin,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: resolvedBorderRadius,
            border: Border.all(
              color: borderSideColor.withValues(alpha: isSelected ? 1.0 : 0.2),
              width: isSelected ? 2 : 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemGrey, context)
                    .withValues(alpha: 0.08),
                blurRadius: elevation ?? (isSelected ? 8 : 4),
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
