import 'config_entry.dart';

/// 更新信息
///
/// 扩展ConfigEntry，添加更新服务特有的属性
class UpdateInfo extends ConfigEntry {
  final String? version;
  final String? checksum;
  final String? region;
  final int? fileSize;
  final String? platform;
  final String? releaseNotes;
  final bool forceUpdate;
  final bool directDownload;

  const UpdateInfo({
    required String url,
    required String description,
    this.version,
    this.checksum,
    this.region,
    this.fileSize,
    this.platform,
    this.releaseNotes,
    this.forceUpdate = false,
    this.directDownload = false,
    Map<String, dynamic>? metadata,
  }) : super(url: url, description: description, metadata: metadata);

  /// 从JSON创建更新信息
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>?;
    final resolvedUrl = json['url'] as String? ??
        json['downloadUrl'] as String? ??
        json['download_url'] as String? ??
        metadata?['downloadUrl'] as String? ??
        metadata?['download_url'] as String? ??
        '';
    final resolvedVersion = json['version'] as String? ??
        json['latestVersion'] as String? ??
        json['latest_version'] as String? ??
        metadata?['version'] as String? ??
        metadata?['latestVersion'] as String? ??
        metadata?['latest_version'] as String?;

    return UpdateInfo(
      url: resolvedUrl,
      description: json['description'] as String? ?? '',
      version: resolvedVersion,
      checksum: json['checksum'] as String?,
      region: json['region'] as String?,
      fileSize: json['fileSize'] as int? ??
          json['file_size'] as int? ??
          metadata?['fileSize'] as int? ??
          metadata?['file_size'] as int?,
      platform: json['platform'] as String? ??
          json['targetPlatform'] as String? ??
          metadata?['platform'] as String?,
      releaseNotes: json['releaseNotes'] as String? ??
          json['release_notes'] as String? ??
          json['notes'] as String? ??
          metadata?['releaseNotes'] as String? ??
          metadata?['release_notes'] as String? ??
          metadata?['notes'] as String?,
      forceUpdate: json['forceUpdate'] as bool? ??
          json['force_update'] as bool? ??
          json['mandatory'] as bool? ??
          metadata?['forceUpdate'] as bool? ??
          metadata?['force_update'] as bool? ??
          metadata?['mandatory'] as bool? ??
          false,
      directDownload: json['directDownload'] as bool? ??
          json['direct_download'] as bool? ??
          json['isDirect'] as bool? ??
          metadata?['directDownload'] as bool? ??
          metadata?['direct_download'] as bool? ??
          metadata?['isDirect'] as bool? ??
          false,
      metadata: metadata,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      if (version != null) 'version': version,
      if (checksum != null) 'checksum': checksum,
      if (region != null) 'region': region,
      if (fileSize != null) 'fileSize': fileSize,
      if (platform != null) 'platform': platform,
      if (releaseNotes != null) 'releaseNotes': releaseNotes,
      'forceUpdate': forceUpdate,
      'directDownload': directDownload,
    });
    return json;
  }

  /// 检查是否为HTTPS连接
  bool get isSecure => url.startsWith('https://');

  /// 获取文件大小的可读格式
  String get fileSizeFormatted {
    if (fileSize == null) return 'Unknown';

    const units = ['B', 'KB', 'MB', 'GB'];
    double size = fileSize!.toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  bool get hasDirectDownload =>
      directDownload ||
      url.contains('/api/v4/file/content/') ||
      url.contains('download=true') ||
      url.endsWith('.apk') ||
      url.endsWith('.zip') ||
      url.endsWith('.exe') ||
      url.endsWith('.msix') ||
      url.endsWith('.msixbundle') ||
      url.endsWith('.appx') ||
      url.endsWith('.appxbundle');

  @override
  String toString() {
    return 'UpdateInfo(url: $url, version: $version, platform: $platform, direct: $hasDirectDownload, size: $fileSizeFormatted)';
  }
}
