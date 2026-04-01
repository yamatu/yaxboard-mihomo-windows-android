import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class OutboundMode extends StatelessWidget {
  const OutboundMode({super.key});

  @override
  Widget build(BuildContext context) {
    final height = getWidgetHeight(2);
    return SizedBox(
      height: height,
      child: Consumer(
        builder: (_, ref, __) {
          final mode = ref.watch(
            patchClashConfigProvider.select(
              (state) => state.mode,
            ),
          );
          return CommonCard(
                onPressed: () {},
                info: Info(
                  label: appLocalizations.outboundMode,
                  iconData: CupertinoIcons.arrow_swap,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 12,
                    bottom: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final item in Mode.values)
                        Flexible(
                          fit: FlexFit.tight,
                          child: ListItem.radio(
                            dense: true,
                            horizontalTitleGap: 4,
                            padding: EdgeInsets.only(
                              left: 12.ap,
                              right: 16.ap,
                            ),
                            delegate: RadioDelegate(
                              value: item,
                              groupValue: mode,
                              onChanged: (value) async {
                                if (value == null) {
                                  return;
                                }
                                globalState.appController.changeMode(value);
                              },
                            ),
                            title: Text(
                              Intl.message(item.name),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
        },
      ),
    );
  }
}

class OutboundModeV2 extends StatelessWidget {
  const OutboundModeV2({super.key});

  Color _getTextColor(BuildContext context, Mode mode) {
    return switch (mode) {
      Mode.rule => CupertinoDynamicColor.resolve(CupertinoColors.label, context),
      Mode.global => CupertinoDynamicColor.resolve(CupertinoColors.label, context),
      Mode.direct => CupertinoDynamicColor.resolve(CupertinoColors.label, context),
    };
  }

  @override
  Widget build(BuildContext context) {
    final height = getWidgetHeight(0.72);
    return SizedBox(
      height: height,
      child: CommonCard(
        padding: EdgeInsets.zero,
        child: Consumer(
          builder: (_, ref, __) {
            final mode = ref.watch(
              patchClashConfigProvider.select(
                (state) => state.mode,
              ),
            );
            final thumbColor = switch (mode) {
              Mode.rule => CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context),
              Mode.global => CupertinoTheme.of(context).primaryColor,
              Mode.direct => CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemGroupedBackground, context),
            };
            return Container(
              constraints: BoxConstraints.expand(),
              child: CommonTabBar<Mode>(
                children: Map.fromEntries(
                  Mode.values.map(
                    (item) => MapEntry(
                      item,
                      Container(
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(),
                        height: height - 16,
                        child: Text(
                          Intl.message(item.name),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: item == mode
                                ? _getTextColor(
                                    context,
                                    item,
                                  )
                                : CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                padding: EdgeInsets.symmetric(horizontal: 8),
                groupValue: mode,
                onValueChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  globalState.appController.changeMode(value);
                },
                thumbColor: thumbColor,
              ),
            );
          },
        ),
      ),
    );
  }
}
