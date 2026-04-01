import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class XBContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final bool safeArea;
  final bool maintainBottomViewPadding;
  const XBContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.safeArea = true,
    this.maintainBottomViewPadding = false,
  });
  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ??
        CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context);
    Widget content = Container(
      padding: padding,
      margin: margin,
      color: bgColor,
      child: child,
    );
    if (safeArea) {
      EdgeInsets safePadding = MediaQuery.paddingOf(context);
      final height = MediaQuery.of(context).size.height;
      if (maintainBottomViewPadding) {
        safePadding = safePadding.copyWith(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        );
      }
      final double realPaddingTop = safePadding.top > height * 0.5 ? 0 : safePadding.top;
      content = Padding(
        padding: EdgeInsets.only(
          left: safePadding.left,
          top: realPaddingTop,
          right: safePadding.right,
          bottom: safePadding.bottom,
        ),
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: content,
        ),
      );
    }
    return content;
  }
}
