import 'dart:async';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_audio/statistics.dart';

/// FFmpeg operations: DASH muxing (video+audio) and MP3 conversion.
/// ffmpeg_kit_flutter_new_audio ships the Audio build — libmp3lame included,
/// muxing needs no encoders (stream copy), keeping the APK ~4x smaller.
class MediaService {
  MediaService._();

  /// Losslessly muxes a video-only stream with an audio stream (stream copy,
  /// no re-encode → original quality preserved, exactly what YouTube serves).
  ///
  /// [onProgress] reports 0..1 derived from FFmpeg statistics (processed
  /// media time vs [duration]) so a 4K merge no longer looks frozen.
  static Future<String> muxVideoAudio(
    String videoPath,
    String audioPath,
    String outPath, {
    Duration? duration,
    void Function(double progress)? onProgress,
  }) async {
    final args = <String>[
      '-y',
      '-i', videoPath,
      '-i', audioPath,
      '-c', 'copy',
    ];
    // +faststart is a private option of the MP4 (mov) muxer only — passing it
    // for other containers (webm/mkv, i.e. VP9/AV1 1440p-8K downloads) can
    // reject the whole command and lose the download. Guard it by extension.
    final lower = outPath.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v') || lower.endsWith('.mov')) {
      args.addAll(['-movflags', '+faststart']);
    }
    args.add(outPath);

    await _run(args, duration: duration, onProgress: onProgress);
    return outPath;
  }

  /// Converts an audio source (m4a/webm) to MP3 192kbps.
  static Future<String> toMp3(
    String inputPath,
    String outPath, {
    Duration? duration,
    void Function(double progress)? onProgress,
  }) async {
    await _run([
      '-y',
      '-i', inputPath,
      '-vn',
      '-c:a', 'libmp3lame',
      '-b:a', '192k',
      outPath,
    ], duration: duration, onProgress: onProgress);
    return outPath;
  }

  /// Executes one FFmpeg command, awaiting completion and reporting progress.
  ///
  /// A generous 20-minute cap guarantees a stuck session can never freeze a
  /// task forever — the task then fails with a retryable error instead.
  static Future<void> _run(
    List<String> args, {
    Duration? duration,
    void Function(double progress)? onProgress,
  }) async {
    final totalMs = duration?.inMilliseconds ?? 0;
    int lastSent = 0;
    final done = Completer<void>();

    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (s) {
        if (!done.isCompleted) done.complete();
      },
      null,
      (Statistics stats) {
        if (onProgress == null || totalMs <= 0) return;
        final ms = stats.getTime();
        if (ms <= 0) return;
        // Throttle UI rebuilds — statistics can fire many times per second.
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastSent < 400) return;
        lastSent = now;
        onProgress((ms / totalMs).clamp(0.0, 0.99));
      },
    );

    try {
      await done.future.timeout(const Duration(minutes: 20));
    } catch (e) {
      try {
        await FFmpegKit.cancel(session.getSessionId());
      } catch (_) {}
      rethrow;
    }

    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      onProgress?.call(1.0);
      return;
    }
    throw Exception('FFmpeg failed (${rc?.getValue()}): ${await _logs(session)}');
  }

  static Future<String> _logs(dynamic session) async {
    try {
      final s = await session.getAllLogsAsString();
      return s.length > 500 ? s.substring(s.length - 500) : s;
    } catch (_) {
      return 'no logs';
    }
  }
}
