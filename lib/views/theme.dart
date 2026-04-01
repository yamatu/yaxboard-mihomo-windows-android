// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'dart:ui' as ui;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/selector.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ThemeModeItem {
  final ThemeMode themeMode;
  final IconData iconData;
  final String label;

  const ThemeModeItem({
    required this.themeMode,
    required this.iconData,
    required this.label,
  });
}

class FontFamilyItem {
  final FontFamily fontFamily;
  final String label;

  const FontFamilyItem({
    required this.fontFamily,
    required this.label,
  });
}

class ThemeView extends StatelessWidget {
  const ThemeView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        spacing: 24,
        children: [
          _ThemeModeItem(),
          _PrimaryColorItem(),
          _PrueBlackItem(),
          _TextScaleFactorItem(),
          const SizedBox(
            height: 64,
          ),
        ],
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  final Widget child;
  final Info info;
  final List<Widget> actions;

  const ItemCard({
    super.key,
    required this.info,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 16,
      children: [
        InfoHeader(
          info: info,
          actions: actions,
        ),
        child,
      ],
    );
  }
}

class _ThemeModeItem extends ConsumerWidget {
  const _ThemeModeItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(themeSettingProvider.select((state) => state.themeMode));
    List<ThemeModeItem> themeModeItems = [
      ThemeModeItem(
        iconData: CupertinoIcons.circle_lefthalf_fill,
        label: appLocalizations.auto,
        themeMode: ThemeMode.system,
      ),
      ThemeModeItem(
        iconData: CupertinoIcons.sun_max,
        label: appLocalizations.light,
        themeMode: ThemeMode.light,
      ),
      ThemeModeItem(
        iconData: CupertinoIcons.moon,
        label: appLocalizations.dark,
        themeMode: ThemeMode.dark,
      ),
    ];
    return ItemCard(
      info: Info(
        label: appLocalizations.themeMode,
        iconData: CupertinoIcons.brightness,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: themeModeItems.length,
          itemBuilder: (_, index) {
            final themeModeItem = themeModeItems[index];
            return CommonCard(
              isSelected: themeModeItem.themeMode == themeMode,
              onPressed: () {
                ref.read(themeSettingProvider.notifier).updateState(
                      (state) => state.copyWith(
                        themeMode: themeModeItem.themeMode,
                      ),
                    );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Icon(themeModeItem.iconData),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Flexible(
                      child: Text(
                        themeModeItem.label,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (_, __) {
            return const SizedBox(
              width: 16,
            );
          },
        ),
      ),
    );
  }
}

class _PrimaryColorItem extends ConsumerStatefulWidget {
  const _PrimaryColorItem();

  @override
  ConsumerState<_PrimaryColorItem> createState() => _PrimaryColorItemState();
}

class _PrimaryColorItemState extends ConsumerState<_PrimaryColorItem> {
  int? _removablePrimaryColor;

  int _calcColumns(double maxWidth) {
    return max((maxWidth / 96).ceil(), 3);
  }

  _handleReset() async {
    final res = await globalState.showMessage(
      message: TextSpan(
        text: appLocalizations.resetTip,
      ),
    );
    if (res != true) {
      return;
    }
    ref.read(themeSettingProvider.notifier).updateState(
      (state) {
        return state.copyWith(
          primaryColors: defaultPrimaryColors,
          primaryColor: defaultPrimaryColor,
          schemeVariant: DynamicSchemeVariant.tonalSpot,
        );
      },
    );
  }

  _handleDel() async {
    if (_removablePrimaryColor == null) {
      return;
    }
    final res = await globalState.showMessage(
      message: TextSpan(
        text: appLocalizations.deleteTip(
          appLocalizations.colorSchemes,
        ),
      ),
    );
    if (res != true) {
      return;
    }
    ref.read(themeSettingProvider.notifier).updateState(
      (state) {
        final newPrimaryColors = List<int>.from(state.primaryColors)
          ..remove(_removablePrimaryColor);
        int? newPrimaryColor = state.primaryColor;
        if (state.primaryColor == _removablePrimaryColor) {
          if (newPrimaryColors.contains(defaultPrimaryColor)) {
            newPrimaryColor = defaultPrimaryColor;
          } else {
            newPrimaryColor = null;
          }
        }
        return state.copyWith(
          primaryColors: newPrimaryColors,
          primaryColor: newPrimaryColor,
        );
      },
    );
    setState(() {
      _removablePrimaryColor = null;
    });
  }

  _handleAdd() async {
    final res = await globalState.showCommonDialog<int>(
      child: _PaletteDialog(),
    );
    if (res == null) {
      return;
    }
    final isExists = ref.read(
      themeSettingProvider.select((state) => state.primaryColors.contains(res)),
    );
    if (isExists && mounted) {
      context.showNotifier(
        appLocalizations.existsTip(
          appLocalizations.colorSchemes,
        ),
      );
      return;
    }
    ref.read(themeSettingProvider.notifier).updateState(
      (state) {
        return state.copyWith(
          primaryColors: List.from(
            state.primaryColors,
          )..add(res),
        );
      },
    );
  }

  _handleChangeSchemeVariant() async {
    final schemeVariant = ref.read(
      themeSettingProvider.select(
        (state) => state.schemeVariant,
      ),
    );
    final value = await globalState.showCommonDialog<DynamicSchemeVariant>(
      child: OptionsDialog<DynamicSchemeVariant>(
        title: appLocalizations.colorSchemes,
        options: DynamicSchemeVariant.values,
        textBuilder: (item) => Intl.message("${item.name}Scheme"),
        value: schemeVariant,
      ),
    );
    if (value == null) {
      return;
    }
    ref.read(themeSettingProvider.notifier).updateState(
      (state) {
        return state.copyWith(
          schemeVariant: value,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm4 = ref.watch(
      themeSettingProvider.select(
        (state) => VM4(
          a: state.primaryColor,
          b: state.primaryColors,
          c: state.schemeVariant,
          d: state.primaryColor == defaultPrimaryColor &&
              intListEquality.equals(state.primaryColors, defaultPrimaryColors),
        ),
      ),
    );
    final primaryColor = vm4.a;
    final primaryColors = [null, ...vm4.b];
    final schemeVariant = vm4.c;
    final isEquals = vm4.d;

    return CommonPopScope(
      onPop: () {
        if (_removablePrimaryColor != null) {
          setState(() {
            _removablePrimaryColor = null;
          });
          return false;
        }
        return true;
      },
      child: ItemCard(
        info: Info(
          label: appLocalizations.themeColor,
          iconData: CupertinoIcons.paintbrush,
        ),
        actions: genActions(
          [
            if (_removablePrimaryColor == null)
              FilledButton(
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _handleChangeSchemeVariant,
                child: Text(Intl.message("${schemeVariant.name}Scheme")),
              ),
            if (_removablePrimaryColor != null)
              FilledButton(
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  setState(() {
                    _removablePrimaryColor = null;
                  });
                },
                child: Text(appLocalizations.cancel),
              ),
            if (_removablePrimaryColor == null && !isEquals)
              CupertinoButton(
                padding: EdgeInsets.all(4),
                minSize: 0,
                onPressed: _handleReset,
                child: Icon(CupertinoIcons.arrow_counterclockwise, size: 20),
              )
          ],
          space: 8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final columns = _calcColumns(constraints.maxWidth);
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final color in primaryColors)
                    Container(
                      clipBehavior: Clip.none,
                      width: itemWidth,
                      height: itemWidth,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          EffectGestureDetector(
                            child: ColorSchemeBox(
                              isSelected: color == primaryColor,
                              primaryColor: color != null ? Color(color) : null,
                              onPressed: () {
                                setState(() {
                                  _removablePrimaryColor = null;
                                });
                                ref
                                    .read(themeSettingProvider.notifier)
                                    .updateState(
                                      (state) => state.copyWith(
                                        primaryColor: color,
                                      ),
                                    );
                              },
                            ),
                            onLongPress: () {
                              setState(() {
                                _removablePrimaryColor = color;
                              });
                            },
                          ),
                          if (_removablePrimaryColor != null &&
                              _removablePrimaryColor == color)
                            Container(
                              color: Colors.white.opacity0,
                              padding: EdgeInsets.all(8),
                              child: CupertinoButton(
                                onPressed: _handleDel,
                                padding: EdgeInsets.all(12),
                                minSize: 0,
                                child: Icon(
                                  color: context.colorScheme.primary,
                                  CupertinoIcons.delete,
                                  size: 30,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_removablePrimaryColor == null)
                    Container(
                      width: itemWidth,
                      height: itemWidth,
                      padding: EdgeInsets.all(
                        4,
                      ),
                      child: CupertinoButton(
                        onPressed: _handleAdd,
                        minSize: 0,
                        padding: EdgeInsets.zero,
                        child: Icon(
                          color: context.colorScheme.primary,
                          CupertinoIcons.add,
                          size: 32,
                        ),
                      ),
                    )
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PrueBlackItem extends ConsumerWidget {
  const _PrueBlackItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prueBlack = ref.watch(
      themeSettingProvider.select(
        (state) => state.pureBlack,
      ),
    );
    return ListItem.switchItem(
      leading: Icon(
        CupertinoIcons.circle_lefthalf_fill,
      ),
      horizontalTitleGap: 12,
      title: Text(
        appLocalizations.pureBlackMode,
        style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.colorScheme.onSurfaceVariant,
            ),
      ),
      delegate: SwitchDelegate(
        value: prueBlack,
        onChanged: (value) {
          ref.read(themeSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  pureBlack: value,
                ),
              );
        },
      ),
    );
  }
}

class _TextScaleFactorItem extends ConsumerWidget {
  const _TextScaleFactorItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScale = ref.watch(
      themeSettingProvider.select(
        (state) => state.textScale,
      ),
    );
    final String process = "${((textScale.scale * 100) as double).round()}%";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: ListItem.switchItem(
            leading: Icon(
              CupertinoIcons.textformat_size,
            ),
            horizontalTitleGap: 12,
            title: Text(
              appLocalizations.textScale,
              style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
            ),
            delegate: SwitchDelegate(
              value: textScale.enable,
              onChanged: (value) {
                ref.read(themeSettingProvider.notifier).updateState(
                      (state) => state.copyWith.textScale(
                        enable: value,
                      ),
                    );
              },
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            spacing: 32,
            children: [
              Expanded(
                child: DisabledMask(
                  status: !textScale.enable,
                  child: ActivateBox(
                    active: textScale.enable,
                    child: CupertinoSlider(
                      min: minTextScale,
                      max: maxTextScale,
                      value: textScale.scale,
                      onChanged: (value) {
                        ref.read(themeSettingProvider.notifier).updateState(
                              (state) => state.copyWith.textScale(
                                scale: value,
                              ),
                            );
                        },
                      ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text(
                  process,
                  style: context.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaletteDialog extends StatefulWidget {
  const _PaletteDialog();

  @override
  State<_PaletteDialog> createState() => _PaletteDialogState();
}

class _PaletteDialogState extends State<_PaletteDialog> {
  final _controller = ValueNotifier<ui.Color>(Colors.transparent);

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: appLocalizations.palette,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(_controller.value.toARGB32());
          },
          child: Text(appLocalizations.confirm),
        ),
      ],
      child: Column(
        children: [
          SizedBox(
            height: 8,
          ),
          SizedBox(
            width: 250,
            height: 250,
            child: Palette(
              controller: _controller,
            ),
          ),
          SizedBox(
            height: 24,
          ),
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, color, __) {
              return PrimaryColorBox(
                primaryColor: color,
                child: FilledButton(
                  onPressed: () {},
                  child: Text(
                    _controller.value.hex,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

