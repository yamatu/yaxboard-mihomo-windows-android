import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/update_check_provider.dart';

class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateCheckProvider);
    final notifier = ref.read(updateCheckProvider.notifier);
    final busy = state.isDownloading || state.isInstalling;

    return CupertinoAlertDialog(
      title: Row(
        children: [
          Icon(
            state.forceUpdate ? CupertinoIcons.exclamationmark_triangle_fill : CupertinoIcons.arrow_down_circle,
            color: state.forceUpdate
                ? CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context)
                : CupertinoTheme.of(context).primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.forceUpdate
                  ? appLocalizations.updateCheckForceUpdate(state.latestVersion ?? '')
                  : appLocalizations.updateCheckNewVersionFound(state.latestVersion ?? ''),
              style: TextStyle(
                color: state.forceUpdate
                    ? CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context)
                    : null,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoTheme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.info,
                  size: 16,
                  color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appLocalizations.updateCheckCurrentVersion(state.currentVersion ?? ''),
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (state.releaseNotes != null && state.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              appLocalizations.updateCheckReleaseNotes,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 140),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(CupertinoColors.systemGrey6, context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Text(
                  state.releaseNotes!,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                  ),
                ),
              ),
            ),
          ],
          if (busy || state.downloadedBytes != null || state.totalBytes != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Download Progress',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: LinearProgressIndicator(
                  value: state.isDownloading
                      ? state.downloadProgress.clamp(0, 1)
                      : (state.isInstalling ? null : state.downloadProgress.clamp(0, 1)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _buildProgressText(state),
              style: TextStyle(
                fontSize: 13,
                color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
              ),
            ),
          ],
          if (state.statusMessage != null && state.statusMessage!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              state.statusMessage!,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoTheme.of(context).primaryColor,
              ),
            ),
          ],
          if (state.error != null && state.error!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context).withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                state.error!,
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!state.forceUpdate && !busy)
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appLocalizations.updateCheckUpdateLater),
          ),
        CupertinoDialogAction(
          isDefaultAction: !state.forceUpdate,
          isDestructiveAction: state.forceUpdate,
          onPressed: busy
              ? null
              : () async {
                  await notifier.startUpdate();
                  if (!context.mounted) return;
                  final currentState = ref.read(updateCheckProvider);
                  if (currentState.error == null && notifier.shouldExitBeforeInstall) {
                    await globalState.appController.handleExit();
                    return;
                  }
                  if (!currentState.forceUpdate && currentState.error == null) {
                    Navigator.of(context).pop();
                  }
                },
          child: Text(
            state.isDownloading
                ? 'Downloading...'
                : state.isInstalling
                    ? 'Launching Installer...'
                    : state.forceUpdate
                        ? appLocalizations.updateCheckMustUpdate
                        : appLocalizations.updateCheckUpdateNow,
          ),
        ),
      ],
    );
  }

  String _buildProgressText(dynamic state) {
    final received = _formatBytes(state.downloadedBytes as int?);
    final total = _formatBytes(state.totalBytes as int?);
    if (state.isInstalling == true) {
      return 'Download completed. Preparing installer...';
    }
    if (received != null && total != null) {
      final percent = ((state.downloadProgress as double) * 100)
          .clamp(0, 100)
          .toStringAsFixed(0);
      return '$percent% ($received / $total)';
    }
    if (received != null) {
      return received;
    }
    return 'Waiting...';
  }

  String? _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }
}
