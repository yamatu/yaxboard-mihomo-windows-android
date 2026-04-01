import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/config/models/update_info.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

final _logger = FileLogger('update_service.dart');

typedef DownloadProgressCallback = void Function(int received, int total);

class UpdateService {
  Future<List<UpdateInfo>> _getAllUpdateSources() async {
    final configUpdates = XBoardConfig.updateList;
    if (configUpdates.isEmpty) {
      throw Exception(appLocalizations.updateCheckNoServerUrlsConfigured);
    }

    _logger.info('Found ${configUpdates.length} update sources');
    return configUpdates;
  }

  Future<Map<String, dynamic>> checkForUpdatesWithFallback() async {
    final updateSources = await _getAllUpdateSources();
    final platform = _getPlatformName();
    final matchedSources = updateSources.where((source) {
      final sourcePlatform = source.platform?.trim().toLowerCase();
      return sourcePlatform == null ||
          sourcePlatform.isEmpty ||
          sourcePlatform == platform;
    }).toList();
    final candidates =
        matchedSources.isNotEmpty ? matchedSources : updateSources;

    for (int i = 0; i < candidates.length; i++) {
      final source = candidates[i];
      try {
        _logger.info(
          'Checking update source ${i + 1}/${candidates.length}: ${source.url}',
        );
        if (source.hasDirectDownload) {
          return await _buildDirectDownloadUpdateInfo(source);
        }
        return await _checkForUpdatesFromUrl(source);
      } catch (e, stackTrace) {
        _logger.error('Update source failed: ${source.url}', e, stackTrace);
        if (i == candidates.length - 1) {
          rethrow;
        }
      }
    }

    throw Exception(appLocalizations.updateCheckAllServersUnavailable);
  }

  Future<Map<String, dynamic>> _buildDirectDownloadUpdateInfo(
    UpdateInfo source,
  ) async {
    final currentVersion = await getCurrentVersion();
    final latestVersion = source.version?.trim().isNotEmpty == true
        ? source.version!.trim()
        : _inferVersionFromUrl(source.url) ?? currentVersion;

    return {
      'currentVersion': currentVersion,
      'latestVersion': latestVersion,
      'hasUpdate': latestVersion != currentVersion || source.forceUpdate,
      'updateUrl': source.url,
      'releaseNotes': source.releaseNotes?.isNotEmpty == true
          ? source.releaseNotes
          : source.description,
      'forceUpdate': source.forceUpdate,
    };
  }

  Future<Map<String, dynamic>> _checkForUpdatesFromUrl(
      UpdateInfo source) async {
    final currentVersion = await getCurrentVersion();
    final platform = _getPlatformName();
    final dio = _createDio();
    final serverUrl = source.url;
    final requestUrl =
        '$serverUrl/api/v1/check-update?version=$currentVersion&platform=$platform';

    _logger.info('Request update info: $requestUrl');

    final response = await dio.get(
      requestUrl,
      options: Options(
        headers: const {
          'Accept': 'application/json',
        },
      ),
    );

    if (response.statusCode != 200) {
      final errorMessage =
          appLocalizations.updateCheckServerError(response.statusCode!);
      if (response.statusCode == 530) {
        throw Exception(
            '$errorMessage - ${appLocalizations.updateCheckServerTemporarilyUnavailable}');
      }
      throw Exception('$errorMessage: ${response.data}');
    }

    final responseData = response.data as Map<String, dynamic>;
    return {
      'currentVersion': currentVersion,
      'latestVersion': responseData['latest_version']?.toString() ?? '',
      'hasUpdate': responseData['update_available'] == true,
      'updateUrl': responseData['download_url']?.toString() ?? '',
      'releaseNotes': responseData['release_notes']?.toString() ?? '',
      'forceUpdate': responseData['force_update'] == true,
    };
  }

  Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  Future<Map<String, dynamic>> checkForUpdates() async {
    return checkForUpdatesWithFallback();
  }

  Future<String> downloadUpdate({
    required String url,
    String? version,
    DownloadProgressCallback? onReceiveProgress,
  }) async {
    final downloadPath = await _buildDownloadPath(url, version);
    final downloadFile = File(downloadPath);
    await downloadFile.parent.create(recursive: true);
    if (await downloadFile.exists()) {
      await downloadFile.delete();
    }

    final dio = _createDio();
    _logger.info('Download update package: $url -> $downloadPath');
    await dio.download(
      url,
      downloadPath,
      deleteOnError: true,
      onReceiveProgress: onReceiveProgress,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
      ),
    );

    return downloadPath;
  }

  Future<void> installUpdate(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Update package not found: $filePath');
    }

    _logger.info('Install update package: $filePath');

    if (Platform.isAndroid) {
      final opened = await app?.openFile(filePath) ?? false;
      if (!opened) {
        throw Exception('无法打开安装程序');
      }
      return;
    }

    if (Platform.isWindows) {
      final extension = p.extension(filePath).toLowerCase();
      if (extension == '.exe') {
        final started = await Process.start(
          filePath,
          const [],
          mode: ProcessStartMode.detached,
          workingDirectory: p.dirname(filePath),
        );
        _logger.info('Started Windows installer pid=${started.pid}');
        return;
      }

      if (extension == '.zip') {
        final installerPath = await _extractWindowsInstaller(filePath);
        final started = await Process.start(
          installerPath,
          const [],
          mode: ProcessStartMode.detached,
          workingDirectory: p.dirname(installerPath),
        );
        _logger.info('Started extracted Windows installer pid=${started.pid}');
        return;
      }

      if (extension == '.msix' ||
          extension == '.msixbundle' ||
          extension == '.appx' ||
          extension == '.appxbundle') {
        final opened = await launchUrl(
          Uri.file(filePath),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          throw Exception('无法打开安装程序');
        }
        return;
      }
    }

    final opened = await launchUrl(
      Uri.file(filePath),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw Exception('无法打开安装程序');
    }
  }

  Future<void> fallbackToExternalDownload(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw Exception('无法打开安装程序');
    }
  }

  bool get shouldExitBeforeInstall => Platform.isWindows;

  String _getPlatformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  Dio _createDio() {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 20);
    dio.options.receiveTimeout = const Duration(minutes: 10);
    dio.options.sendTimeout = const Duration(seconds: 20);
    dio.options.validateStatus = (status) => status != null && status < 600;

    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        if (kDebugMode) {
          client.badCertificateCallback = (
            X509Certificate cert,
            String host,
            int port,
          ) {
            _logger.warning(
                'Ignore certificate validation in debug mode: $host:$port');
            return true;
          };
        }
        return client;
      };
    }
    return dio;
  }

  Future<String> _extractWindowsInstaller(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final outputDir = p.join(
      p.dirname(zipPath),
      '${p.basenameWithoutExtension(zipPath)}_extracted',
    );
    final outputDirectory = Directory(outputDir);
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
    await outputDirectory.create(recursive: true);

    String? installerPath;
    for (final file in archive.files) {
      final normalizedName = file.name.replaceAll('\\', '/');
      final destinationPath = p.joinAll([
        outputDir,
        ...normalizedName.split('/').where((part) => part.isNotEmpty),
      ]);

      if (file.isFile) {
        final outFile = File(destinationPath);
        await outFile.parent.create(recursive: true);
        final data = file.content as List<int>;
        await outFile.writeAsBytes(data, flush: true);

        final ext = p.extension(destinationPath).toLowerCase();
        final baseName = p.basename(destinationPath).toLowerCase();
        if (installerPath == null &&
            (ext == '.exe' || ext == '.msix' || ext == '.appx') &&
            !baseName.contains('vc_redist')) {
          installerPath = outFile.path;
        }
      } else {
        await Directory(destinationPath).create(recursive: true);
      }
    }

    if (installerPath == null) {
      throw Exception('No installer found in update archive');
    }

    return installerPath;
  }

  String? _inferVersionFromUrl(String url) {
    final match = RegExp(r'(\d+\.\d+\.\d+(?:[\.\-]\d+)?)').firstMatch(url);
    return match?.group(1);
  }

  Future<String> _buildDownloadPath(String url, String? version) async {
    final uri = Uri.parse(url);
    final rawFileName =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final sanitizedVersion =
        (version ?? 'latest').replaceAll(RegExp(r'[^\w\.\-]+'), '_');
    final fallbackExtension = _defaultExtensionForPlatform();
    final extension = p.extension(rawFileName).isNotEmpty
        ? p.extension(rawFileName)
        : fallbackExtension;
    final baseName = p.basenameWithoutExtension(rawFileName).isNotEmpty
        ? p.basenameWithoutExtension(rawFileName)
        : 'yaboard_update_$sanitizedVersion';
    final fileName = '${baseName}_$sanitizedVersion$extension';
    final tempPath = await appPath.tempPath;
    return p.join(tempPath, 'updates', fileName);
  }

  String _defaultExtensionForPlatform() {
    if (Platform.isAndroid) return '.apk';
    if (Platform.isWindows) return '.exe';
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isLinux) return '.AppImage';
    return '.bin';
  }
}
