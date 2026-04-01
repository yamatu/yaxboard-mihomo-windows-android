import 'package:fl_clash/xboard/core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/update_check_state.dart';
import '../services/update_service.dart';

final _logger = FileLogger('update_check_provider.dart');

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final updateCheckProvider =
    StateNotifierProvider<UpdateCheckNotifier, UpdateCheckState>((ref) {
  final updateService = ref.watch(updateServiceProvider);
  return UpdateCheckNotifier(updateService: updateService);
});

class UpdateCheckNotifier extends StateNotifier<UpdateCheckState> {
  final UpdateService _updateService;

  UpdateCheckNotifier({
    required UpdateService updateService,
  })  : _updateService = updateService,
        super(const UpdateCheckState());

  Future<void> initialize() async {
    _logger.info('Initialize update check');
    await checkForUpdates();
  }

  Future<void> refresh() async {
    _logger.info('Refresh update check');
    await checkForUpdates();
  }

  Future<void> checkForUpdates() async {
    if (!mounted) return;
    state = state.copyWith(
      isChecking: true,
      error: null,
      statusMessage: null,
    );

    try {
      final currentVersion = await _updateService.getCurrentVersion();
      _logger.info('Current version: $currentVersion');

      state = state.copyWith(currentVersion: currentVersion);

      final updateInfo = await _updateService.checkForUpdatesWithFallback();
      if (!mounted) return;

      state = state.copyWith(
        isChecking: false,
        hasUpdate: updateInfo['hasUpdate'] as bool? ?? false,
        latestVersion: updateInfo['latestVersion']?.toString(),
        updateUrl: updateInfo['updateUrl']?.toString(),
        releaseNotes: updateInfo['releaseNotes']?.toString(),
        forceUpdate: updateInfo['forceUpdate'] as bool? ?? false,
        downloadProgress: 0,
        downloadedBytes: 0,
        totalBytes: 0,
        downloadedFilePath: null,
        isDownloading: false,
        isInstalling: false,
        error: null,
      );

      if (state.hasUpdate) {
        _logger.info('New version found: ${state.latestVersion}');
      } else {
        _logger.info('Already up to date');
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      _logger.error('Check update failed', e, stackTrace);
      state = state.copyWith(
        isChecking: false,
        error: e.toString(),
      );
    }
  }

  Future<void> startUpdate() async {
    if (!mounted) return;
    final updateUrl = state.updateUrl;
    if (updateUrl == null || updateUrl.isEmpty) {
      state = state.copyWith(
        error: 'Missing update download URL',
      );
      return;
    }

    state = state.copyWith(
      isDownloading: true,
      isInstalling: false,
      error: null,
      statusMessage: 'Downloading update package...',
      downloadProgress: 0,
      downloadedBytes: 0,
      totalBytes: 0,
    );

    try {
      final filePath = await _updateService.downloadUpdate(
        url: updateUrl,
        version: state.latestVersion,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          final progress = total > 0 ? received / total : 0.0;
          state = state.copyWith(
            downloadProgress: progress,
            downloadedBytes: received,
            totalBytes: total > 0 ? total : null,
            statusMessage: 'Downloading update package...',
          );
        },
      );

      if (!mounted) return;

      state = state.copyWith(
        isDownloading: false,
        isInstalling: true,
        downloadedFilePath: filePath,
        downloadProgress: 1,
        statusMessage: 'Download completed. Preparing installer...',
      );

      await _updateService.installUpdate(filePath);

      if (!mounted) return;

      state = state.copyWith(
        isInstalling: false,
        statusMessage: 'Installer launched.',
      );
    } catch (e, stackTrace) {
      if (!mounted) return;
      _logger.error('Download or install update failed', e, stackTrace);
      state = state.copyWith(
        isDownloading: false,
        isInstalling: false,
        error: e.toString(),
        statusMessage: null,
      );
    }
  }

  bool get shouldExitBeforeInstall => _updateService.shouldExitBeforeInstall;
}
