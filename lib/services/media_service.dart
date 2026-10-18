import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

/// FFmpeg operations: DASH muxing (video+audio) and MP3 conversion.
/// ffmpeg_kit_flutter_new_audio ships the Audio build — libmp3lame included,
/// muxing needs no encoders (stream copy), keeping the APK ~4x smaller.
class MediaService {
  MediaService._();

  /// Losslessly muxes a video-only stream with an audio stream (stream copy,
  /// no re-encode → original quality preserved, exactly what YouTube serves).
  static Future<String> muxVideoAudio(String videoPath, String audioPath, String outPath) async {
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i', videoPath,
      '-i', audioPath,
      '-c', 'copy',
      '-movflags', '+faststart',
      outPath,
    ]);
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) return outPath;
    throw Exception('Mux failed (${rc?.getValue()}): ${await _logs(session)}');
  }

  /// Converts an audio source (m4a/webm) to MP3 192kbps.
  static Future<String> toMp3(String inputPath, String outPath) async {
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i', inputPath,
      '-vn',
      '-c:a', 'libmp3lame',
      '-b:a', '192k',
      outPath,
    ]);
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) return outPath;
    throw Exception('MP3 conversion failed (${rc?.getValue()}): ${await _logs(session)}');
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
