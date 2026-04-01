class UpdateCheckState {
  final bool isChecking;
  final bool hasUpdate;
  final bool isDownloading;
  final bool isInstalling;
  final String? currentVersion;
  final String? latestVersion;
  final String? updateUrl;
  final String? releaseNotes;
  final bool forceUpdate;
  final double downloadProgress;
  final int? downloadedBytes;
  final int? totalBytes;
  final String? downloadedFilePath;
  final String? statusMessage;
  final String? error;
  const UpdateCheckState({
    this.isChecking = false,
    this.hasUpdate = false,
    this.isDownloading = false,
    this.isInstalling = false,
    this.currentVersion,
    this.latestVersion,
    this.updateUrl,
    this.releaseNotes,
    this.forceUpdate = false,
    this.downloadProgress = 0,
    this.downloadedBytes,
    this.totalBytes,
    this.downloadedFilePath,
    this.statusMessage,
    this.error,
  });
  UpdateCheckState copyWith({
    bool? isChecking,
    bool? hasUpdate,
    bool? isDownloading,
    bool? isInstalling,
    String? currentVersion,
    String? latestVersion,
    String? updateUrl,
    String? releaseNotes,
    bool? forceUpdate,
    double? downloadProgress,
    int? downloadedBytes,
    int? totalBytes,
    String? downloadedFilePath,
    String? statusMessage,
    String? error,
  }) {
    return UpdateCheckState(
      isChecking: isChecking ?? this.isChecking,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      isDownloading: isDownloading ?? this.isDownloading,
      isInstalling: isInstalling ?? this.isInstalling,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      updateUrl: updateUrl ?? this.updateUrl,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      forceUpdate: forceUpdate ?? this.forceUpdate,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedFilePath: downloadedFilePath ?? this.downloadedFilePath,
      statusMessage: statusMessage ?? this.statusMessage,
      error: error,
    );
  }
}
