import 'package:fl_clash/common/color.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CommonChip extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ChipType type;
  final Widget? avatar;

  const CommonChip({
    super.key,
    required this.label,
    this.onPressed,
    this.avatar,
    this.type = ChipType.action,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryLabel = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final separator = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );

    return GestureDetector(
      onTap: type == ChipType.delete ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: separator, width: 0.5),
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemFill,
            context,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[
              avatar!,
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: secondaryLabel,
              ),
            ),
            if (type == ChipType.delete) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onPressed,
                child: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 16,
                  color: secondaryLabel,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
