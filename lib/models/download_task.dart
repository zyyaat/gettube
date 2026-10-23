import 'package:dio/dio.dart';

import 'quality_option.dart';

enum DownloadStatus { queued, fetching, downloading, processing, saving, paused, waitingForWifi, completed, failed, canceled }

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

  /// 0..1 while the final file is being prepared (merging/converting).
  /// 0 = not started or indeterminate.
  double processProgress = 0;

  /// Video duration — used to turn FFmpeg statistics into a real %.
  Duration? duration;
  String? filePath; // final saved path/uri
  String? savedUri; // MediaStore content uri when public on Android 10+
  String? error;

  /// Where the file will be / was saved, e.g. "Download/GetTube/Video".
  String? destinationLabel;

  CancelToken? cancelToken;

  /// Pre-resolved stream URLs taken from the manifest that was ALREADY
  /// fetched for the quality sheet — the download starts on them instantly
  /// (SnapTube-style). On 403/410 the engine re-mints via the client ladder.
  String? presetMainUrl;
  String? presetAudioUrl;
  String? presetAudioExt;

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
      status == DownloadStatus.saving ||
      status == DownloadStatus.waitingForWifi;

  // ---------------- persistence ----------------
  // The queue used to live ONLY in memory — when Android killed the process
  // (background, memory pressure, user swipes the app away), every running
  // download silently VANISHED with no error shown. Serializing each task
  // lets DownloadManager restore the queue on the next launch and resume
  // from the bytes already on disk.

  Map<String, dynamic> toJson() => {
        'id': id,
        'videoId': videoId,
        'title': title,
        'thumb': thumbnailUrl,
        'channel': channel,
        'type': type.name,
        'status': status.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'received': received,
        'total': total,
        'durationMs': duration?.inMilliseconds,
        'filePath': filePath,
        'savedUri': savedUri,
        'error': error,
        'dest': destinationLabel,
        'option': {
          'kind': option.kind.name,
          'videoTag': option.videoTag,
          'audioTag': option.audioTag,
          'label': option.label,
          'container': option.container,
          'codec': option.codec,
          'fps': option.fps,
          'sizeBytes': option.sizeBytes,
          'ext': option.ext,
          'srcExt': option.srcExt,
          'mp3': option.mp3,
          'recommended': option.recommended,
        },
      };

  factory DownloadTask.fromJson(Map<String, dynamic> j) {
    final o = (j['option'] as Map?) ?? const {};
    return DownloadTask(
      id: (j['id'] ?? '').toString(),
      videoId: (j['videoId'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      thumbnailUrl: (j['thumb'] ?? '').toString(),
      channel: (j['channel'] ?? '').toString(),
      type: DownloadType.values.firstWhere(
        (e) => e.name == j['type'],
        orElse: () => DownloadType.video,
      ),
      option: QualityOption(
        kind: QualityKind.values.firstWhere(
          (e) => e.name == o['kind'],
          orElse: () => QualityKind.muxed,
        ),
        videoTag: (o['videoTag'] as num?)?.toInt() ?? 0,
        audioTag: (o['audioTag'] as num?)?.toInt(),
        label: (o['label'] ?? '').toString(),
        container: (o['container'] ?? '').toString(),
        codec: (o['codec'] ?? '').toString(),
        fps: (o['fps'] as num?)?.toInt() ?? 0,
        sizeBytes: (o['sizeBytes'] as num?)?.toInt() ?? 0,
        ext: (o['ext'] ?? 'mp4').toString(),
        srcExt: (o['srcExt'] ?? 'mp4').toString(),
        mp3: o['mp3'] == true,
        recommended: o['recommended'] == true,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (j['createdAt'] as num?)?.toInt() ?? 0),
    )
      ..status = DownloadStatus.values.firstWhere(
        (e) => e.name == j['status'],
        orElse: () => DownloadStatus.failed,
      )
      ..received = (j['received'] as num?)?.toInt() ?? 0
      ..total = (j['total'] as num?)?.toInt() ?? 0
      ..duration = j['durationMs'] != null
          ? Duration(milliseconds: (j['durationMs'] as num).toInt())
          : null
      ..filePath = j['filePath']?.toString()
      ..savedUri = j['savedUri']?.toString()
      ..error = j['error']?.toString()
      ..destinationLabel = j['dest']?.toString();
  }
}
