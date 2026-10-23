import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/i18n.dart';
import '../models/download_task.dart';
import '../models/quality_option.dart';
import '../models/saved_file.dart';
import 'crash_log.dart';
import 'media_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

/// The server stopped honoring Range requests mid-flight — segmented
/// splitting is impossible, the caller falls back to one stream.
class _RangeIgnored {}

/// The download queue engine.
///
/// Features:
///  • parallel downloads (user-configurable 1..10)
///  • pause / resume via HTTP Range requests (.part files kept on disk)
///  • automatic retry-safe temp files, cancel with cleanup
///  • automatic final-file preparation for HD/4K/8K quality
///  • MP3 conversion for audio tasks
///  • waits for Wi-Fi when mobile data is disabled (user setting)
///  • publishes to the user-selected save location
class DownloadManager extends ChangeNotifier {
  DownloadManager._internal();
  static final DownloadManager instance = DownloadManager._internal();

  final List<DownloadTask> tasks = []; // newest first

  int maxConcurrent = 2;

  /// Save location: 'default' | 'sdcard' | 'custom' | 'app'.
  String saveLocation = 'default';
  String? sdVolumeId;
  String? customTreeUri;
  String customFolderLabel = '';
  bool mobileDataAllowed = true;

  // ---------------- queue persistence ----------------
  // FIX for "the download VANISHES with no error": the queue used to live
  // only in RAM. Android kills background processes all the time (memory
  // pressure, user swipes the app away) — every running download then
  // silently disappeared. Now every status change is persisted, and on the
  // next launch the queue is restored: finished/failed tasks stay visible,
  // interrupted ones return to `queued` and resume FROM DISK (single-stream
  // Range or .lenN sidecars) without losing a byte.
  static const String _queueKey = 'queue_persist_v2';
  bool _restored = false;

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _queueKey, tasks.map((t) => jsonEncode(t.toJson())).toList());
    } catch (e) {
      CrashLog.write('queue persist failed: $e');
    }
  }

  /// Call ONCE after app launch (after Flutter bindings are ready).
  /// Restores the queue from the last run and restarts interrupted work —
  /// so a killed process turns into a visible, resuming queue instead of
  /// a silent disappearance.
  Future<void> restoreQueue() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_queueKey) ?? [];
      for (final line in raw) {
        try {
          final t = DownloadTask.fromJson(jsonDecode(line) as Map<String, dynamic>);
          if (t.id.isEmpty || tasks.any((x) => x.id == t.id)) continue;
          // Anything that was mid-flight belongs back in the queue — the
          // engine resumes from the bytes already on disk.
          if (t.isActive || t.status == DownloadStatus.waitingForWifi) {
            t.status = DownloadStatus.queued;
            t.received = 0;
          }
          tasks.add(t);
        } catch (_) {
          // one corrupt entry must not kill the whole restore
        }
      }
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
      _pump(); // resume interrupted downloads right away
    } catch (e) {
      CrashLog.write('queue restore failed: $e');
    }
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    maxRedirects: 5,
    validateStatus: (c) => c != null && c < 500,
  ));

  final Map<String, String> _stopIntent = {}; // taskId -> 'pause' | 'cancel'

  bool _wakelockHeld = false;
  Timer? _netTimer;
  bool _metered = false;

  /// Slots are occupied ONLY by real running work (fetching/downloading/
  /// processing). Queued tasks are the ones WAITING for a slot — counting
  /// them here made the scheduler see phantom-busy slots whenever the
  /// number of queued tasks reached maxConcurrent (easy with 2+ quick taps),
  /// and then NOTHING ever started: every pump recomputed free = 0 and the
  /// queue froze in "في الانتظار" forever. This was the stuck-queue root
  /// cause since v1.0 — the early releases only got away with it because
  /// slow manifest fetches made back-to-back enqueues rare.
  ///
  /// Safe against double-starts: _run() sets `fetching` synchronously before
  /// its first await, so by the time any later pump pass looks at the task
  /// it already occupies a real slot.
  int get activeCount => tasks
      .where((t) =>
          t.status == DownloadStatus.fetching ||
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.processing)
      .length;

  /// Anything that still needs the device awake (queued, running, saving).
  bool get hasActive => tasks.any((t) => t.isActive);

  // ---------------- queue control ----------------

  Future<void> enqueue({
    required String videoId,
    required String title,
    required String thumbnailUrl,
    required String channel,
    required QualityOption option,
    required Duration? duration,
    StreamManifest? presetManifest,
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
    task.duration = duration;
    // SnapTube-style instant start: the quality sheet already fetched this
    // manifest seconds ago — hand its stream URLs straight to the engine so
    // the first HTTP GET fires immediately (no re-resolution round-trips).
    if (presetManifest != null) {
      for (final s in presetManifest.streams) {
        if (s.tag == option.videoTag) {
          task.presetMainUrl = s.url.toString();
          break;
        }
      }
      if (option.audioTag != null) {
        for (final s in presetManifest.streams) {
          if (s.tag == option.audioTag) {
            task.presetAudioUrl = s.url.toString();
            task.presetAudioExt = s.container.name == 'mp4' ? 'm4a' : 'webm';
            break;
          }
        }
      }
    }
    task.destinationLabel = _destinationLabel(type);

    tasks.insert(0, task);
    notifyListeners();
    unawaited(_persist());
    // START THE QUEUE NOW — permissions must never gate the download (a hung
    // permission dialog used to strand tasks in "waiting" forever).
    _pump();
    unawaited(NotificationService.ensurePermission());
    unawaited(_ensureStoragePermission());
  }

  Future<void> _ensureStoragePermission() async {
    try {
      // Only needed for direct public writes on Android 9-.
      if (Platform.isAndroid && saveLocation != 'app') {
        final v = int.tryParse(Platform.version.split('.').first) ?? 0;
        if (v <= 28 && await Permission.storage.isDenied) {
          await Permission.storage.request();
        }
      }
    } catch (_) {}
  }

  /// Human-friendly destination folder shown on download cards.
  String _destinationLabel(DownloadType type) {
    final leaf = type == DownloadType.video ? StorageDirs.video : StorageDirs.audio;
    switch (saveLocation) {
      case 'custom':
        if (customTreeUri != null && customFolderLabel.isNotEmpty) return customFolderLabel;
        return 'GetTube/$leaf';
      case 'app':
        return 'GetTube/$leaf';
      case 'sdcard':
        return 'SD/Download/GetTube/$leaf';
      default:
        return 'Download/GetTube/$leaf';
    }
  }

  void pause(DownloadTask t) {
    if (t.status == DownloadStatus.queued || t.status == DownloadStatus.waitingForWifi) {
      _set(t, DownloadStatus.paused);
      _syncWakelock();
      return;
    }
    if (t.isActive) {
      _stopIntent[t.id] = 'pause';
      t.cancelToken?.cancel('pause');
    }
  }

  void resume(DownloadTask t) {
    if (t.status == DownloadStatus.paused || t.status == DownloadStatus.failed || t.status == DownloadStatus.canceled || t.status == DownloadStatus.waitingForWifi) {
      t.error = null;
      _set(t, DownloadStatus.queued);
      _pump();
    }
  }

  /// Alias used by the downloads tile: re-queue a failed/canceled task.
  void retry(DownloadTask t) => resume(t);

  void cancel(DownloadTask t) {
    if (t.status == DownloadStatus.queued || t.status == DownloadStatus.waitingForWifi) {
      _cleanupParts(t);
      _set(t, DownloadStatus.canceled);
      _syncNetTimer();
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
      unawaited(_persist());
    }
  }

  void clearFinished() {
    tasks.removeWhere((t) => !t.isActive);
    notifyListeners();
    unawaited(_persist());
  }

  /// Re-evaluates the queue right now (called when a relevant setting
  /// changes, e.g. the user enables mobile data).
  void refresh() => _pump();

  void _pump() {
    if (_pumping) {
      _pumpQueued = true; // a pump is already in flight — re-run it once more
      return;
    }
    unawaited(_pumpAsync());
  }

  bool _pumping = false;
  bool _pumpQueued = false;

  Future<void> _pumpAsync() async {
    _pumping = true;
    try {
      do {
        _pumpQueued = false;
        try {
          await _pumpPass();
        } catch (e, st) {
          // A dead pump pass must never strand tasks — log it; the network
          // timer below re-runs the pump as a self-healing safety net.
          CrashLog.write('PUMP failed: $e', st);
        }
        _syncWakelock();
        _syncNetTimer();
      } while (_pumpQueued);
    } finally {
      _pumping = false;
    }
  }

  Future<void> _pumpPass() async {
    // Refresh the metered (mobile data) state before assigning slots.
    // If the platform check fails, keep the last known state instead of
    // killing the whole pump (that used to strand tasks in queued forever).
    try {
      _metered = await StorageService.isMetered();
    } catch (e) {
      CrashLog.write('network check failed: $e');
    }
    int free = maxConcurrent - activeCount;
    for (final t in List<DownloadTask>.from(tasks)) {
      if (free <= 0) break;
      // Released from the Wi-Fi gate? Do NOT continue — fall through so
      // it STARTS in this very pass (the old code broke out here and
      // nothing re-triggered the pump afterwards, so the task sat in
      // queued forever).
      if (t.status == DownloadStatus.waitingForWifi) {
        if (!(mobileDataAllowed || !_metered)) continue;
        _set(t, DownloadStatus.queued);
      }
      if (t.status != DownloadStatus.queued) continue;
      // Mobile data disabled + metered network -> hold for Wi-Fi.
      if (!mobileDataAllowed && _metered) {
        _set(t, DownloadStatus.waitingForWifi);
        continue;
      }
      free--;
      unawaited(_run(t));
    }
  }

  /// While any task waits for Wi-Fi — or sits queued (safety net) — poll
  /// the network/settings state so work resumes automatically the moment
  /// Wi-Fi is back or mobile data is allowed.
  void _syncNetTimer() {
    final need = tasks.any((t) => t.status == DownloadStatus.waitingForWifi || t.status == DownloadStatus.queued);
    if (need && _netTimer == null) {
      _netTimer = Timer.periodic(const Duration(seconds: 12), (_) => _pump());
    } else if (!need && _netTimer != null) {
      _netTimer!.cancel();
      _netTimer = null;
    }
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
      // WHY A CLIENT LADDER (the "YouTube rejected the link" fix):
      // Stream URLs are minted per YouTube API client, and Google gates them:
      //  • ANDROID (with androidSdkVersion) now requires a PO Token -> its
      //    URLs 403 immediately for third-party downloads. This was the
      //    root cause of high-quality (DASH) downloads failing.
      //  • ANDROID_VR similar situation on many videos.
      //  • androidSdkless / TVHTML5 / IOS mint URLs that download fine
      //    without PO Tokens (as long as the HTTP User-Agent matches the
      //    minting client).
      // So every pass resolves FRESH URLs from ONE pinned client and
      // downloads them with that client's exact User-Agent. On 403/401/410
      // the next client mints brand-new URLs — .part bytes are kept for
      // resuming, nothing is ever deleted.
      late String mainPath;
      String? audioPath;
      bool resolved = false;

      // FAST PATH — SnapTube-style instant start: the quality sheet already
      // fetched this manifest seconds ago, so download those URLs RIGHT NOW
      // with zero re-resolution. YouTube stream URLs stay valid for hours.
      // On 403/401/410 (or a stall) we fall through to the client ladder
      // below — .part/.seg bytes are kept and resumed, nothing is lost.
      final audioReady = task.option.audioTag == null || task.presetAudioUrl != null;
      if (task.presetMainUrl != null && audioReady) {
        try {
          task.total = task.option.sizeBytes;
          task.received = 0;
          _set(task, DownloadStatus.downloading);
          mainPath = '${tmpDir.path}/${task.id}.main.${task.option.srcExt}';
          await _downloadToFile(task.presetMainUrl!, mainPath, task, _uaForClient(YoutubeApiClient.androidSdkless));
          audioPath = null;
          if (task.option.audioTag != null && task.presetAudioUrl != null) {
            audioPath = '${tmpDir.path}/${task.id}.audio.${task.presetAudioExt ?? 'm4a'}';
            await _downloadToFile(
              task.presetAudioUrl!,
              audioPath,
              task,
              _uaForClient(YoutubeApiClient.androidSdkless),
              counted: false,
            );
          }
          resolved = true;
        } on DioException catch (e) {
          // ANY fast-path failure hands over to the client ladder — the
          // preset URLs are one shot only. This used to accept ONLY
          // 403/401/410/404, so a plain connection hiccup (connectionError,
          // socket reset — routine on mobile data) RETHREW and killed the
          // task in ~2 seconds while the ladder sat right below, unused.
          if (!_stopIntent.containsKey(task.id)) {
            final code = e.response?.statusCode;
            CrashLog.write(
                'FAST-START ${e.type}${code == null ? '' : ' $code'} — switching to client ladder (tag ${task.option.videoTag})');
            audioPath = null;
          } else {
            rethrow;
          }
        }
      }

      // One manifest fetch PER CLIENT for both video+audio (the old code
      // re-fetched the same manifest for the audio tag — a whole extra
      // round-trip before the first byte could land).
      final manifests = <YoutubeApiClient, StreamManifest>{};
      Future<StreamManifest?> manifestFor(YoutubeApiClient client) async {
        if (manifests.containsKey(client)) return manifests[client];
        final m = await YoutubeService
            .getManifestWithClient(VideoId(task.videoId), client)
            .timeout(const Duration(seconds: 30));
        manifests[client] = m;
        return m;
      }

      bool botGated = false;
      for (int pass = 0; pass < _clientLadder.length; pass++) {
        final client = _clientLadder[pass];
        // YouTube's bot gate is per-NETWORK, not per-client: once it answers,
        // every remaining innertube client returns the SAME gate within
        // seconds. Fast-forward straight to the watch-page client (safari)
        // instead of burning ~15s per doomed client (real user log:
        // 45s of retries that all died with the same reason).
        if (botGated && client != YoutubeApiClient.safari) continue;
        final isLastClient = pass == _clientLadder.length - 1;
        try {
          final manifest = await manifestFor(client);
          final mainStream = _pickStream(manifest, task.option.videoTag);
          // Quality not offered by this client (rare) — try the next one.
          if (mainStream == null) continue;

          task.total = task.option.sizeBytes;
          task.received = 0;
          _set(task, DownloadStatus.downloading);

          mainPath = '${tmpDir.path}/${task.id}.main.${task.option.srcExt}';
          await _downloadToFile(mainStream.url.toString(), mainPath, task, _uaForClient(client));

          audioPath = null;
          if (task.option.audioTag != null) {
            final audioStream = _pickStream(manifest, task.option.audioTag!);
            if (audioStream == null) continue;
            final audioExt =
                audioStream.container.name == 'mp4' ? 'm4a' : 'webm';
            audioPath = '${tmpDir.path}/${task.id}.audio.$audioExt';
            await _downloadToFile(
              audioStream.url.toString(),
              audioPath,
              task,
              _uaForClient(client),
              counted: false,
            );
          }
          resolved = true;
          break; // this client worked — done resolving/downloading
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          // A stall watchdog cancel (no user intent) is a dead socket, not
          // a failure — retry the same tag with the next client, .part kept.
          final stalled = e.type == DioExceptionType.cancel && !_stopIntent.containsKey(task.id);
          final retriable = stalled || code == 403 || code == 401 || code == 410 || code == 404;
          if (!isLastClient && retriable && !_stopIntent.containsKey(task.id)) {
            CrashLog.write(
                'DL ${stalled ? 'STALL' : code} from client ${_clientName(client)} (tag ${task.option.videoTag}) — switching client');
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue; // fresh client, fresh URLs, same .part files
          }
          rethrow;
        } on TimeoutException {
          if (!isLastClient && !_stopIntent.containsKey(task.id)) {
            CrashLog.write('manifest timeout from client ${_clientName(client)} — switching client');
            continue;
          }
          rethrow;
        } on YoutubeExplodeException catch (e) {
          // youtube_explode runs on package:http, NOT dio — its failures
          // (VideoUnplayable, TransientFailure, rate limits, innertube 4xx)
          // are NOT DioExceptions. They used to escape this ladder entirely
          // and kill the task within ~2 seconds. Next client instead.
          if (_botGateExp.hasMatch(e.toString())) {
            botGated = true;
            CrashLog.write(
                'BOT GATE via ${_clientName(client)} — fast-forwarding to watch-page client');
            continue;
          }
          if (!isLastClient && !_stopIntent.containsKey(task.id)) {
            CrashLog.write('manifest ${e.runtimeType} from client ${_clientName(client)} — switching client');
            await Future<void>.delayed(const Duration(milliseconds: 400));
            continue;
          }
          rethrow;
        } on SocketException {
          // Raw socket failure while fetching the manifest — same policy.
          if (!isLastClient && !_stopIntent.containsKey(task.id)) {
            CrashLog.write('manifest socket error from client ${_clientName(client)} — switching client');
            await Future<void>.delayed(const Duration(milliseconds: 400));
            continue;
          }
          rethrow;
        }
      }
      // Every client exhausted without a usable stream for this tag.
      if (!resolved) {
        throw Exception(botGated ? L.botGateHint : L.qualityNotAvailable);
      }

      // 2) mux / convert — with LIVE progress (a 4K merge used to look
      // frozen because nothing on the card moved during this phase).
      String outPath = mainPath;
      String finalExt = task.option.ext;
      if (audioPath != null) {
        _set(task, DownloadStatus.processing);
        task.processProgress = 0;
        outPath = '${tmpDir.path}/${task.id}.out.${task.option.ext}';
        try {
          await MediaService.muxVideoAudio(
            mainPath, audioPath, outPath,
            duration: task.duration,
            onProgress: (p) {
              task.processProgress = p;
              notifyListeners();
            },
          );
        } catch (_) {
          // Never lose a high-quality download: MKV accepts every codec
          // combination YouTube serves (VP9/AV1 + Opus included), so retry
          // the lossless mux into an .mkv before giving up.
          outPath = '${tmpDir.path}/${task.id}.out.mkv';
          await MediaService.muxVideoAudio(
            mainPath, audioPath, outPath,
            duration: task.duration,
            onProgress: (p) {
              task.processProgress = p;
              notifyListeners();
            },
          );
          finalExt = 'mkv';
        }
        _tryDelete(mainPath);
        _tryDelete(audioPath);
      } else if (task.option.mp3) {
        _set(task, DownloadStatus.processing);
        task.processProgress = 0;
        outPath = '${tmpDir.path}/${task.id}.out.mp3';
        await MediaService.toMp3(
          mainPath, outPath,
          duration: task.duration,
          onProgress: (p) {
            task.processProgress = p;
            notifyListeners();
          },
        );
        _tryDelete(mainPath);
      }

      // 3) publish to destination — copying a 2-4GB 4K file takes a while,
      // so give it its own visible state instead of a frozen "processing".
      _set(task, DownloadStatus.saving);
      _stopIntent.remove(task.id);
      final subDir =
          task.type == DownloadType.video ? StorageDirs.video : StorageDirs.audio;
      final displayName =
          '${sanitizeFileName(task.title)} [${task.option.label}].$finalExt';
      final mime = StorageService.mimeFor(finalExt, task.type == DownloadType.video);
      SavedFile saved;
      if (saveLocation == 'custom' && customTreeUri != null) {
        try {
          saved = await StorageService.publishToTree(
            tempPath: outPath,
            treeUri: customTreeUri!,
            displayName: displayName,
            mime: mime,
            thumbUrl: task.thumbnailUrl,
          );
        } catch (e) {
          // Never lose a finished file: fall back to the public folder.
          CrashLog.write('CUSTOM FOLDER save failed — falling back: $e');
          saved = await StorageService.publish(
            tempPath: outPath,
            displayName: displayName,
            mime: mime,
            subDir: subDir,
            location: 'default',
            thumbUrl: task.thumbnailUrl,
          );
        }
      } else {
        saved = await StorageService.publish(
          tempPath: outPath,
          displayName: displayName,
          mime: mime,
          subDir: subDir,
          location: saveLocation == 'app' ? 'app' : saveLocation,
          volumeId: sdVolumeId,
          thumbUrl: task.thumbnailUrl,
        );
      }
      task.filePath = saved.path.isNotEmpty ? saved.path : (saved.uri ?? '');
      task.savedUri = saved.uri;
      if (saved.folderLabel.isNotEmpty) task.destinationLabel = saved.folderLabel;
      _set(task, DownloadStatus.completed);
      unawaited(NotificationService.showDone(task.title, displayName));
    } catch (e) {
      final intent = _stopIntent.remove(task.id);
      final wasCanceled = e is DioException && e.type == DioExceptionType.cancel;
      if (wasCanceled && intent == 'pause') {
        task.speedBps = 0;
        _set(task, DownloadStatus.paused);
      } else if (wasCanceled && intent == 'cancel') {
        _cleanupParts(task);
        _set(task, DownloadStatus.canceled);
      } else {
        task.speedBps = 0;
        if (wasCanceled) {
          // Canceled with NO user intent = the stall watchdog gave up on a
          // dead connection after every retry. This used to be recorded as
          // "canceled" — a state the user never asked for and, before the
          // history section existed, it vanished from the UI entirely. It
          // is a FAILURE: keep the resume bytes, show retry.
          CrashLog.write('DL dead connection (stall watchdog) — failing visibly: ${task.title}');
          task.error = L.downloadFailedGeneric;
        } else if (e is DioException && e.response?.statusCode == 403) {
          CrashLog.write('DOWNLOAD 403: ${task.title}', e.stackTrace);
          task.error = L.streamRejected;
        } else if (_botGateExp.hasMatch(e.toString())) {
          // YouTube answered the whole ladder with its bot gate — show the
          // honest network-level explanation instead of a generic failure.
          CrashLog.write('BOT GATE (final): ${task.title} — $e');
          task.error = L.botGateHint;
        } else {
          // Keep the raw error in the diagnostics log so storage/processing
          // failures can be diagnosed from the in-app report screen.
          CrashLog.write('DOWNLOAD FAILED [${task.option.label}]: $e', e is Error ? e.stackTrace : null);
          // Show a friendly, human message — raw technical details stay in
          // the diagnostics log only.
          task.error = L.downloadFailedGeneric;
        }
        _set(task, DownloadStatus.failed);
      }
    } finally {
      _pump();
    }
  }

  /// Finds a stream by tag inside an already-fetched manifest (pure lookup,
  /// zero network). Returns null when the tag is absent — the ladder then
  /// moves to the next client.
  StreamInfo? _pickStream(StreamManifest? manifest, int tag) {
    if (manifest == null) return null;
    for (final s in manifest.streams) {
      if (s.tag == tag) return s;
    }
    return null;
  }

  /// The client ladder. Order = preference, each entry is a DIFFERENT
  /// enforcement surface YouTube gates independently:
  ///  1. androidSdkless — ANDROID without androidSdkVersion: mints URLs that
  ///     need NO PO Token on healthy IPs (mirrors yt-dlp's android_sdkless).
  ///  2. mediaConnect — MEDIA_CONNECT_FRONTEND (Chromecast family): the
  ///     client that kept minting PO-Token-free URLs longest (yt-dlp's
  ///     mconnect fallback).
  ///  3. tv — TVHTML5: very reliable direct URLs when not gated.
  ///  4. ios — minted URLs download cleanly with the iOS app UA.
  ///  5. androidVr — last innertube app client, high-quality capable.
  ///  6. safari — WEB client via the watch page: a plain-browser surface
  ///     that often still answers when every app client is bot-gated.
  ///     (tvSimplyEmbedded skipped: deprecated upstream — YouTube now
  ///     requires authentication for it, so it can never yield streams.)
  ///
  /// 2026 reality: YouTube now bot-gates whole networks ("Sign in to
  /// confirm you're not a bot"). When that message appears, every remaining
  /// innertube client will return the SAME gate — so [_run] fast-forwards
  /// to the watch-page client and fails with a clear hint instead of
  /// burning a minute on doomed retries.
  static final List<YoutubeApiClient> _clientLadder = [
    YoutubeApiClient.androidSdkless,
    YoutubeApiClient.mediaConnect,
    YoutubeApiClient.tv,
    YoutubeApiClient.ios,
    YoutubeApiClient.androidVr,
    YoutubeApiClient.safari,
  ];

  /// Matches YouTube's bot-gate playability reason. Shared across all
  /// innertube clients for a gated network — seeing it once means the
  /// rest of the app-client ladder is wasted time.
  static final RegExp _botGateExp =
      RegExp(r"not a bot|confirm you.?re|Sign in to confirm", caseSensitive: false);

  /// Human-readable client name for diagnostics.
  static String _clientName(YoutubeApiClient c) {
    final ctx = c.payload['context']['client'] as Map?;
    final name = ctx?['clientName']?.toString() ?? '?';
    final sdk = ctx?['androidSdkVersion']?.toString();
    return sdk == null ? name : '$name(sdk$sdk)';
  }

  /// User-Agent of the client that minted the URL. Google's video servers
  /// enforce that the download UA matches the minting client — a mismatched
  /// or generic UA is rejected with 403. Every [YoutubeApiClient] payload
  /// carries its canonical `userAgent`; the switch below is only a fallback
  /// for payloads without one.
  static String _uaForClient(YoutubeApiClient c) {
    final payloadUa = c.payload['userAgent'];
    if (payloadUa is String && payloadUa.isNotEmpty) return payloadUa;
    final ctx = c.payload['context']['client'] as Map?;
    final name = ctx?['clientName']?.toString() ?? '';
    final ver = ctx?['clientVersion']?.toString() ?? '0';
    switch (name) {
      case 'IOS':
        return 'com.google.ios.youtube/$ver (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
      case 'ANDROID_VR':
        return 'com.google.android.apps.youtube.vr.oculus/$ver (Linux; U; Android 12; Quest 3) gzip';
      case 'TVHTML5':
      case 'TVHTML5_SIMPLY_EMBEDDED_PLAYER':
        return 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version,gzip(gfe)';
      default: // ANDROID (both sdkless and sdk variants)
        return 'com.google.android.youtube/$ver (Linux; U; Android 11) gzip';
    }
  }

  static const String _chromeUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Resumable streaming download. First tries the minting client's exact
  /// User-Agent, then a desktop-Chrome fingerprint as a generic fallback
  /// (covers UA-enforcing carrier networks). Keeps `.part` bytes across
  /// attempts and continues with a Range request; tracks live speed.
  Future<void> _downloadToFile(
    String url,
    String savePath,
    DownloadTask task,
    String primaryUa, {
    bool counted = true,
  }) async {
    final uas = [primaryUa, _chromeUa];
    for (int i = 0; i < uas.length; i++) {
      final isLast = i == uas.length - 1;
      try {
        await _downloadToFileWithUa(
          url,
          savePath,
          task,
          uas[i],
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
    // Probe the real size + Range support with a 1-byte request. The probe
    // token is cancelled right after the headers are read — on a non-Range
    // server the 200 body would otherwise be the WHOLE file.
    int total = 0;
    bool ranged = false;
    final probeToken = CancelToken();
    try {
      final probe = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'range': 'bytes=0-0', 'user-agent': ua},
          validateStatus: (c) => c != null && c < 500,
        ),
        cancelToken: probeToken,
      );
      final cr = probe.headers.value('content-range');
      if (probe.statusCode == 206 && cr != null) {
        final m = RegExp(r'/(\d+)\s*$').firstMatch(cr);
        if (m != null) {
          total = int.parse(m.group(1)!);
          ranged = true;
        }
      }
    } finally {
      if (!probeToken.isCancelled) probeToken.cancel('probe-done');
    }

    if (ranged && total > _minSegmentedBytes) {
      // Multi-connection download (NewPipe/IDM/SnapTube style): the file is
      // split into N byte ranges fetched in parallel — bypasses single-TCP
      // throttling and saturates the link. Any segment failure self-heals.
      try {
        await _downloadSegmented(url, savePath, task, ua, total, counted: counted);
        return;
      } on _RangeIgnored {
        // Server flipped to full-body responses (or the file could not be
        // preallocated) — wipe the sparse file + sidecars: the single-stream
        // path must start from a clean, contiguous file.
        _wipeSegmentedState(savePath);
      }
    }
    await _downloadSingleStream(url, savePath, task, ua, counted: counted);
  }

  /// Removes sidecars AND the preallocated `.part` itself — after segmented
  /// writes the file contains scattered regions, so it is useless for the
  /// contiguous single-stream path.
  void _wipeSegmentedState(String savePath) {
    for (int i = 0; i < _segments; i++) {
      for (final suffix in ['.len$i', '.seg$i']) {
        try {
          final f = File('$savePath$suffix');
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    try {
      final f = File(savePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Classic single-connection resumable download (kept for small files,
  /// non-Range servers, and as the segmented fallback). Adds a stall
  /// watchdog: no bytes for 20s cancels the request so the outer ladders
  /// can retry — the task can never hang silently on a dead socket.
  Future<void> _downloadSingleStream(
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
    Timer? stall;

    void resetStall() {
      stall?.cancel();
      stall = Timer(const Duration(seconds: 20), () {
        if (!_stopIntent.containsKey(task.id)) token.cancel('stall');
      });
    }

    try {
      resetStall();
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (counted) task.received = received;
        resetStall();

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
    } finally {
      stall?.cancel();
    }
  }

  static const int _segments = 4;
  static const int _minSegmentedBytes = 8 * 1024 * 1024;
  static const int _sidecarFlushBytes = 4 * 1024 * 1024; // resume granularity

  /// Multi-connection download (NewPipe/IDM/SnapTube style): the file is
  /// split into [_segments] byte ranges fetched in parallel — bypasses
  /// single-TCP throttling and saturates the link.
  ///
  /// Each worker writes DIRECTLY into its own region of the final
  /// preallocated file (no `.seg` copies, no 4GB concat pass at the end —
  /// that silent copy used to keep big downloads stuck on "preparing").
  /// A tiny text sidecar `.lenN` tracks how far segment N got, so a paused /
  /// failed task resumes exactly where it stopped. Incomplete rounds
  /// self-heal from the sidecars, with a fresh cancel token each round so
  /// pause/cancel keeps working.
  Future<void> _downloadSegmented(
    String url,
    String savePath,
    DownloadTask task,
    String ua,
    int total, {
    required bool counted,
  }) async {
    String lenPath(int i) => '$savePath.len$i';
    final segLen = (total + _segments - 1) ~/ _segments;
    int rangeLen(int i) =>
        (i == _segments - 1) ? total - segLen * (_segments - 1) : segLen;

    int readLen(int i) {
      try {
        final f = File(lenPath(i));
        return f.existsSync() ? int.tryParse(f.readAsStringSync().trim()) ?? 0 : 0;
      } catch (_) {
        return 0;
      }
    }

    void writeLen(int i, int n) {
      try {
        File(lenPath(i)).writeAsStringSync('$n');
      } catch (_) {}
    }

    void deleteSidecars() {
      for (int i = 0; i < _segments; i++) {
        try {
          final f = File(lenPath(i));
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      // Orphaned segments from the old (.segN + concat) scheme.
      for (int i = 0; i < _segments; i++) {
        try {
          final f = File('$savePath.seg$i');
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }

    final outFile = File(savePath);
    RandomAccessFile raf;
    try {
      // Fully downloaded in a previous run (merge was pending when the
      // process got killed)? The .part file then has the EXACT total size
      // and no sidecars — treat it as complete, nothing to fetch.
      if (outFile.existsSync() &&
          outFile.lengthSync() == total &&
          !List.generate(_segments, (i) => File(lenPath(i))).any((f) => f.existsSync())) {
        if (counted) {
          task.received = task.total;
          notifyListeners();
        }
        return;
      }
      // append (keeps earlier bytes when resuming) then pin the exact size —
      // a sparse preallocation on Android, instant even for 4K files.
      raf = outFile.openSync(mode: FileMode.append);
      await raf.truncate(total);
    } catch (_) {
      // Disk full / no preallocation support → segmented needs a fixed-size
      // file. Fall back to the single-stream path (writes incrementally).
      deleteSidecars();
      throw _RangeIgnored();
    }

    final sw = Stopwatch()..start();
    int lastSample = 0;
    double ema = 0;
    int round = 0;

    try {
      final side = List.generate(_segments, readLen);
      int receivedNow() {
        int s = 0;
        for (final v in side) {
          s += v;
        }
        return s;
      }

      if (counted) {
        task.received = receivedNow();
        lastSample = task.received;
        notifyListeners();
      }

      while (true) {
        final roundToken = CancelToken();
        task.cancelToken = roundToken;
        final futures = <Future<void>>[];
        for (int i = 0; i < _segments; i++) {
          final start = i * segLen;
          final end = (i == _segments - 1) ? total - 1 : (i + 1) * segLen - 1;
          final from = start + side[i];
          if (from > end) continue;
          futures.add(_downloadRange(
            url, raf, lenPath(i), start, side[i], end, task, ua, roundToken,
            flushEvery: _sidecarFlushBytes,
            onSegBytes: (n, {bool force = false}) {
              side[i] = n;
              if (force) writeLen(i, n);
              if (!counted) return;
              task.received = receivedNow();
              if (sw.elapsedMilliseconds >= 500) {
                final nowR = task.received;
                final inst = (nowR - lastSample) * 1000 / sw.elapsedMilliseconds;
                ema = ema == 0 ? inst : ema * 0.7 + inst * 0.3;
                task.speedBps = ema;
                lastSample = nowR;
                sw.reset();
                notifyListeners();
              }
            },
          ));
        }
        if (futures.isEmpty) break;
        try {
          await Future.wait(futures);
        } catch (e) {
          // A stall cancels the whole round — refresh counts from the
          // sidecars and re-issue only the missing ranges. Real errors
          // propagate after a few rounds; pause/cancel always propagates.
          if (_stopIntent.containsKey(task.id)) rethrow;
          if (e is _RangeIgnored) rethrow;
          round++;
          if (round >= 6) rethrow;
          for (int i = 0; i < _segments; i++) {
            writeLen(i, side[i]); // persist exact resume points
          }
          await Future<void>.delayed(const Duration(milliseconds: 800));
          continue;
        }
        // Requests "succeeded" — verify every segment REALLY reached its
        // range end (a stray 416 must never leave the file short).
        final allDone = List.generate(_segments, (i) => side[i] >= rangeLen(i)).every((v) => v);
        if (allDone) break;
        round++;
        if (round >= 6) {
          throw Exception('segmented download stalled after $round rounds');
        }
      }

      if (counted) {
        task.received = task.total;
        task.speedBps = 0;
        notifyListeners();
      }
      await raf.flush();
      deleteSidecars(); // SUCCESS only — on failure they stay as resume points
    } finally {
      try {
        raf.closeSync();
      } catch (_) {}
    }
  }

  /// One parallel worker: fetches the fixed byte range and writes it DIRECTLY
  /// at its absolute offsets inside the shared preallocated file. [raf] is
  /// one handle; every write is a `setPosition` + `writeFromSync` pair with
  /// no await in between, so parallel workers can never interleave a pair.
  Future<void> _downloadRange(
    String url,
    RandomAccessFile raf,
    String lenPath,
    int segStart,
    int alreadyHave,
    int end,
    DownloadTask task,
    String ua,
    CancelToken token, {
    required int flushEvery,
    required void Function(int segReceived, {bool force}) onSegBytes,
  }) async {
    int received = alreadyHave; // bytes of THIS segment on disk
    int sinceFlush = 0;
    Timer? stall;

    void resetStall() {
      stall?.cancel();
      stall = Timer(const Duration(seconds: 20), () {
        if (!_stopIntent.containsKey(task.id)) token.cancel('stall');
      });
    }

    try {
      final resp = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'range': 'bytes=${segStart + received}-$end', 'user-agent': ua},
          validateStatus: (c) => c != null && c < 500,
        ),
        cancelToken: token,
      );
      if (resp.statusCode == 416) return; // range already complete
      if (resp.statusCode != 206) {
        // 200 = server ignored the Range header → cannot split safely.
        throw _RangeIgnored();
      }
      resetStall();
      await for (final chunk in resp.data!.stream) {
        raf.setPositionSync(segStart + received);
        raf.writeFromSync(chunk);
        received += chunk.length;
        sinceFlush += chunk.length;
        final force = sinceFlush >= flushEvery;
        if (force) {
          writeLenSafe(lenPath, received);
          sinceFlush = 0;
        }
        onSegBytes(received, force: force);
        resetStall();
      }
      writeLenSafe(lenPath, received); // exact resume point on round end
    } finally {
      stall?.cancel();
      // Persist the exact position even on error/cancel — this is what makes
      // resume never re-download an already-stored byte.
      writeLenSafe(lenPath, received);
    }
  }

  void writeLenSafe(String lenPath, int n) {
    try {
      File(lenPath).writeAsStringSync('$n');
    } catch (_) {}
  }

  // ---------------- helpers ----------------

  void _set(DownloadTask t, DownloadStatus s) {
    t.status = s;
    notifyListeners();
    // Persist on every STATE change (rare, cheap) — progress counters are
    // NOT persisted because they are re-derived from the bytes on disk
    // when a killed run resumes.
    unawaited(_persist());
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
    _netTimer?.cancel();
    _dio.close();
    super.dispose();
  }
}
