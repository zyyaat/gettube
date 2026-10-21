import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/i18n.dart';
import '../models/download_task.dart';
import '../models/quality_option.dart';
import 'crash_log.dart';
import 'media_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

/// The download queue engine.
///
/// Features:
///  • parallel downloads (configurable concurrency)
///  • pause / resume via HTTP Range requests (.part files kept on disk)
///  • automatic retry-safe temp files, cancel with cleanup
///  • auto-mux of video+audio (DASH) through FFmpeg for HD/4K/8K
///  • MP3 conversion for audio tasks
///  • publishes to public Downloads (MediaStore) or app directory
class DownloadManager extends ChangeNotifier {
  DownloadManager._internal();
  static final DownloadManager instance = DownloadManager._internal();

  final List<DownloadTask> tasks = []; // newest first

  int maxConcurrent = 2;
  bool savePublic = true;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    maxRedirects: 5,
    validateStatus: (c) => c != null && c < 500,
  ));

  final Map<String, String> _stopIntent = {}; // taskId -> 'pause' | 'cancel'

  bool _wakelockHeld = false;

  int get activeCount =>
      tasks.where((t) => t.status == DownloadStatus.queued || t.status == DownloadStatus.fetching || t.status == DownloadStatus.downloading || t.status == DownloadStatus.processing).length;

  bool get hasActive => activeCount > 0;

  // ---------------- queue control ----------------

  Future<void> enqueue({
    required String videoId,
    required String title,
    required String thumbnailUrl,
    required String channel,
    required QualityOption option,
    required Duration? duration,
  }) async {
    final type = option.kind == QualityKind.audioOnly ? DownloadType.audio : DownloadType.video;
    final task = DownloadTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_${option.videoTag}',
      videoId: videoId,
      title: title,
      thumbnailUrl: thumbnailUrl,
      channel: channel,
      type: type,
      option: option,
      createdAt: DateTime.now(),
    )..total = option.sizeBytes;

    tasks.insert(0, task);
    notifyListeners();
    await NotificationService.ensurePermission();
    await _ensureStoragePermission();
    _pump();
  }

  Future<void> _ensureStoragePermission() async {
    try {
      // Only needed for direct public writes on Android 9-.
      if (Platform.isAndroid && savePublic) {
        final v = int.tryParse(Platform.version.split('.').first) ?? 0;
        if (v <= 28 && await Permission.storage.isDenied) {
          await Permission.storage.request();
        }
      }
    } catch (_) {}
  }

  void pause(DownloadTask t) {
    if (t.status == DownloadStatus.queued) {
      _set(t, DownloadStatus.paused);
      return;
    }
    if (t.isActive) {
      _stopIntent[t.id] = 'pause';
      t.cancelToken?.cancel('pause');
    }
  }

  void resume(DownloadTask t) {
    if (t.status == DownloadStatus.paused || t.status == DownloadStatus.failed || t.status == DownloadStatus.canceled) {
      t.error = null;
      _set(t, DownloadStatus.queued);
      _pump();
    }
  }

  /// Alias used by the downloads tile: re-queue a failed/canceled task.
  void retry(DownloadTask t) => resume(t);

  void cancel(DownloadTask t) {
    if (t.status == DownloadStatus.queued) {
      _cleanupParts(t);
      _set(t, DownloadStatus.canceled);
      return;
    }
    if (t.isActive) {
      _stopIntent[t.id] = 'cancel';
      t.cancelToken?.cancel('cancel');
    }
  }

  void remove(DownloadTask t) {
    if (t.isActive) {
      cancel(t);
    } else {
      tasks.remove(t);
      notifyListeners();
    }
  }

  void clearFinished() {
    tasks.removeWhere((t) => !t.isActive);
    notifyListeners();
  }

  void _pump() {
    int free = maxConcurrent - activeCount;
    for (final t in List<DownloadTask>.from(tasks)) {
      if (free <= 0) break;
      if (t.status != DownloadStatus.queued) continue;
      free--;
      unawaited(_run(t));
    }
    _syncWakelock();
  }

  // ---------------- worker ----------------

  Future<void> _run(DownloadTask task) async {
    _stopIntent.remove(task.id);
    try {
      _set(task, DownloadStatus.fetching);

      final tmpDir = Directory('${(await getTemporaryDirectory()).path}/dl');
      await tmpDir.create(recursive: true);

      // 1) resolve + download.
      //
      // CRITICAL: with the ANDROID client, YouTube rejects (HTTP 403)
      // downloading MORE THAN ONE stream minted from the SAME manifest.
      // High-quality DASH downloads need TWO streams (video + audio), so
      // each stream is resolved from its OWN freshly-minted manifest.
      // If a 403/410 still happens (expired URL, carrier IP rotation,
      // rate limiting), the whole resolve is retried once more with
      // everything fresh — .part bytes are kept for resuming.
      late String mainPath;
      String? audioPath;
      for (int pass = 0; pass < 2; pass++) {
        try {
          final mainStream = await _resolveStream(task, task.option.videoTag);

          task.total = task.option.sizeBytes;
          task.received = 0;
          _set(task, DownloadStatus.downloading);

          mainPath = '${tmpDir.path}/${task.id}.main.${task.option.srcExt}';
          await _downloadToFile(mainStream.url.toString(), mainPath, task);

          audioPath = null;
          if (task.option.audioTag != null) {
            // SEPARATE manifest for the paired audio — two streams from one
            // manifest is exactly what YouTube rejects with 403.
            final audioStream =
                await _resolveStream(task, task.option.audioTag!);
            final audioExt =
                audioStream.container.name == 'mp4' ? 'm4a' : 'webm';
            audioPath = '${tmpDir.path}/${task.id}.audio.$audioExt';
            await _downloadToFile(
              audioStream.url.toString(),
              audioPath,
              task,
              counted: false,
            );
          }
          break;
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          final retriable = code == 403 || code == 410 || code == 404;
          if (pass == 0 && retriable && !_stopIntent.containsKey(task.id)) {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue; // fresh manifests, same .part files
          }
          rethrow;
        }
      }

      // 2) mux / convert
      String outPath = mainPath;
      String finalExt = task.option.ext;
      if (audioPath != null) {
        _set(task, DownloadStatus.processing);
        outPath = '${tmpDir.path}/${task.id}.out.${task.option.ext}';
        try {
          await MediaService.muxVideoAudio(mainPath, audioPath, outPath);
        } catch (_) {
          // Never lose a high-quality download: MKV accepts every codec
          // combination YouTube serves (VP9/AV1 + Opus included), so retry
          // the lossless mux into an .mkv before giving up.
          outPath = '${tmpDir.path}/${task.id}.out.mkv';
          await MediaService.muxVideoAudio(mainPath, audioPath, outPath);
          finalExt = 'mkv';
        }
        _tryDelete(mainPath);
        _tryDelete(audioPath);
      } else if (task.option.mp3) {
        _set(task, DownloadStatus.processing);
        outPath = '${tmpDir.path}/${task.id}.out.mp3';
        await MediaService.toMp3(mainPath, outPath);
        _tryDelete(mainPath);
      }

      // 3) publish to destination
      _stopIntent.remove(task.id);
      final subDir =
          task.type == DownloadType.video ? StorageDirs.video : StorageDirs.audio;
      final displayName =
          '${sanitizeFileName(task.title)} [${task.option.label}].$finalExt';
      final saved = await StorageService.publish(
        tempPath: outPath,
        displayName: displayName,
        mime: StorageService.mimeFor(finalExt, task.type == DownloadType.video),
        subDir: subDir,
        public: savePublic,
      );
      task.filePath = saved.path;
      task.savedUri = saved.uri;
      _set(task, DownloadStatus.completed);
      unawaited(NotificationService.showDone(task.title, displayName));
    } catch (e) {
      final intent = _stopIntent.remove(task.id);
      final wasCanceled = e is DioException && e.type == DioExceptionType.cancel;
      if (wasCanceled && intent == 'pause') {
        task.speedBps = 0;
        _set(task, DownloadStatus.paused);
      } else if (wasCanceled) {
        _cleanupParts(task);
        _set(task, DownloadStatus.canceled);
      } else {
        task.speedBps = 0;
        if (e is DioException && e.response?.statusCode == 403) {
          CrashLog.write('DOWNLOAD 403: ${task.title}', e.stackTrace);
          task.error = L.streamRejected;
        } else {
          // Keep the raw error in the diagnostics log so mux/FFmpeg/storage
          // failures can be diagnosed from the in-app error log.
          CrashLog.write('DOWNLOAD FAILED [${task.option.label}]: $e', e is Error ? e.stackTrace : null);
          task.error = e.toString();
        }
        _set(task, DownloadStatus.failed);
      }
    } finally {
      _pump();
    }
  }

  /// Resolves a single stream by tag from a FRESH manifest (fresh minted
  /// URLs, independent download session).
  Future<StreamInfo> _resolveStream(DownloadTask task, int tag) async {
    final manifest = await YoutubeService.getManifest(VideoId(task.videoId));
    for (final s in manifest.streams) {
      if (s.tag == tag) return s;
    }
    throw Exception(L.qualityNotAvailable);
  }

  /// User-Agents mirroring the clients youtube_explode mints stream URLs
  /// with. Some networks enforce that the download UA matches the client
  /// that requested the manifest — mismatched UA is rejected with 403.
  static const List<String> _uaLadder = [
    // ANDROID client (default manifest source)
    'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    // IOS client (secondary manifest source)
    'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    // Desktop web (watch page client)
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
  ];

  /// Resumable streaming download with a User-Agent fallback ladder.
  /// Keeps `.part` bytes across attempts and continues with a Range
  /// request; tracks live speed on the task.
  Future<void> _downloadToFile(
    String url,
    String savePath,
    DownloadTask task, {
    bool counted = true,
  }) async {
    for (int i = 0; i < _uaLadder.length; i++) {
      final isLast = i == _uaLadder.length - 1;
      try {
        await _downloadToFileWithUa(
          url,
          savePath,
          task,
          _uaLadder[i],
          counted: counted,
        );
        return;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        // 403/401: try the next client fingerprint with the same .part.
        if (!isLast && (code == 403 || code == 401)) continue;
        rethrow;
      }
    }
  }

  Future<void> _downloadToFileWithUa(
    String url,
    String savePath,
    DownloadTask task,
    String ua, {
    bool counted = true,
  }) async {
    final token = CancelToken();
    task.cancelToken = token;

    final file = File(savePath);
    int received = file.existsSync() ? file.lengthSync() : 0;

    final Response<ResponseBody> resp = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'range': 'bytes=$received-', 'user-agent': ua},
        validateStatus: (c) => c != null && c < 500,
      ),
      cancelToken: token,
    );

    // 416 = we already have everything (previous run finished the body)
    if (resp.statusCode == 416) {
      if (counted) task.received = task.total;
      notifyListeners();
      return;
    }
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      // 403/410 etc: keep the .part bytes and surface the status code —
      // the UA ladder (outer) and fresh-manifest retry (_run) decide what
      // to do next. Never delete partial data here.
      throw DioException.badResponse(
        statusCode: resp.statusCode ?? 500,
        requestOptions: resp.requestOptions,
        response: resp,
      );
    }
    if (resp.statusCode == 200) received = 0; // server ignored Range → restart

    final sink = file.openWrite(mode: received > 0 ? FileMode.append : FileMode.write);
    final sw = Stopwatch()..start();
    int lastBytes = received;
    double ema = 0;

    try {
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (counted) task.received = received;

        if (sw.elapsedMilliseconds >= 500) {
          final inst = (received - lastBytes) * 1000 / sw.elapsedMilliseconds;
          ema = ema == 0 ? inst : ema * 0.7 + inst * 0.3;
          if (counted) task.speedBps = ema;
          lastBytes = received;
          sw.reset();
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      if (counted) task.speedBps = 0;
      notifyListeners();
    } catch (e) {
      try {
        await sink.flush();
        await sink.close();
      } catch (_) {}
      rethrow;
    }
  }

  // ---------------- helpers ----------------

  void _set(DownloadTask t, DownloadStatus s) {
    t.status = s;
    notifyListeners();
  }

  void _cleanupParts(DownloadTask t) {
    try {
      final tmp = Directory('${Directory.systemTemp.path}/dl');
      if (tmp.existsSync()) {
        for (final f in tmp.listSync()) {
          if (f is File && f.path.contains(t.id)) {
            f.deleteSync();
          }
        }
      }
    } catch (_) {}
    // also the real cache dir used by path_provider
    getTemporaryDirectory().then((d) {
      final tmp2 = Directory('${d.path}/dl');
      if (tmp2.existsSync()) {
        for (final f in tmp2.listSync()) {
          if (f is File && f.path.contains(t.id)) {
            f.deleteSync();
          }
        }
      }
    }).catchError((_) {});
  }

  void _tryDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _syncWakelock() {
    if (hasActive) {
      if (!_wakelockHeld) {
        _wakelockHeld = true;
        WakelockPlus.enable();
      }
    } else if (_wakelockHeld) {
      _wakelockHeld = false;
      WakelockPlus.disable();
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }
}
