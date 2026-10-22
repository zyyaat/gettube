import 'package:dio/dio.dart';

import 'quality_option.dart';

enum DownloadStatus { queued, fetching, downloading, processing, paused, waitingForWifi, completed, failed, canceled }

enum DownloadType { video, audio }

/// One unit of work in the download queue. Mutable by design; the
/// [DownloadManager] owns all mutation and notifies listeners.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.videoId,
    required this.title,
    required this.thumbnailUrl,
    required this.channel,
    required this.type,
    required this.option,
    required this.createdAt,
  });

  final String id;
  final String videoId;
  final String title;
  final String thumbnailUrl;
  final String channel;
  final DownloadType type;
  final QualityOption option;
  final DateTime createdAt;

  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int total = 0;
  double speedBps = 0;
  String? filePath; // final saved path/uri
  String? savedUri; // MediaStore content uri when public on Android 10+
  String? error;

  /// Where the file will be / was saved, e.g. "Download/GetTube/Video".
  String? destinationLabel;

  CancelToken? cancelToken;

  double get progress {
    if (total <= 0) return 0;
    final p = received / total;
    return p.clamp(0.0, 1.0);
  }

  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.fetching ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.processing ||
      status == DownloadStatus.waitingForWifi;
}
