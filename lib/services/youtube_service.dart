import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/quality_option.dart';

/// Wraps YoutubeExplode: search, video metadata, and the full stream manifest.
///
/// YouTube exposes two stream families:
///  - muxed  (video+audio): usually only low resolutions (360p/720p)
///  - adaptive: videoOnly (up to 8K) + audioOnly streams
/// Every quality YouTube offers is listed — nothing is paywalled in GetTube.
class YoutubeService {
  YoutubeService._();

  static final YoutubeExplode _yt = YoutubeExplode();

  /// Cache of quality options per video (manifest fetch is expensive).
  static final Map<String, List<QualityOption>> _optionsCache = {};

  /// Cache of the LAST manifest per video — passed to the download engine so
  /// the HTTP GET starts IMMEDIATELY on quality pick (no re-resolution).
  /// YouTube stream URLs stay valid for hours; on 403 the engine re-mints.
  static final Map<String, StreamManifest> _manifestCache = {};

  static StreamManifest? cachedManifest(String videoId) => _manifestCache[videoId];

  // ---------------- Search ----------------

  /// Returns the first search page. Keep the returned [VideoSearchList]
  /// around to call `.nextPage()` for pagination.
  static Future<VideoSearchList> search(String query) => _yt.search.search(query);

  // ---------------- Video ----------------

  static Future<Video> getVideo(String idOrUrl) => _yt.videos.get(VideoId(idOrUrl));

  /// Accepts a bare 11-char id or any youtube URL.
  static String? extractVideoId(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(t)) return t;
    if (t.contains('youtu')) {
      try {
        return VideoId(t).value;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // ---------------- Quality options ----------------

  static Future<List<QualityOption>> getQualityOptions(Video video) async {
    final cached = _optionsCache[video.id.value];
    if (cached != null) return cached;

    StreamManifest manifest;
    try {
      manifest = await _yt.videos.streams.getManifest(video.id);
    } catch (_) {
      // One transient retry — YouTube occasionally hiccups.
      manifest = await _yt.videos.streams.getManifest(video.id);
    }

    final options = <QualityOption>[];

    final muxed = manifest.muxed.toList()
      ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
    for (final s in muxed) {
      options.add(QualityOption(
        kind: QualityKind.muxed,
        videoTag: s.tag,
        label: _videoLabel(s.qualityLabel, s.videoResolution.height, s.framerate.framesPerSecond.toInt()),
        container: _containerLabel(s.container.name, prettyVideoCodec(s.videoCodec)),
        codec: prettyVideoCodec(s.videoCodec),
        fps: s.framerate.framesPerSecond.toInt(),
        sizeBytes: s.size.totalBytes,
        ext: s.container.name,
        srcExt: s.container.name,
      ));
    }

    // Audio candidates for pairing (prefer AAC/m4a for maximum compatibility).
    final audios = manifest.audioOnly.toList()..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    final bestAac = _pickAudio(audios, 'mp4a');
    final bestOpus = _pickAudio(audios, 'opus');

    // Video-only streams: every resolution YouTube offers, desc.
    final videoOnly = manifest.videoOnly.toList()
      ..sort((a, b) {
        final byH = b.videoResolution.height.compareTo(a.videoResolution.height);
        if (byH != 0) return byH;
        return b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond);
      });

    for (final s in videoOnly) {
      final container = s.container.name; // mp4 | webm
      final pair = container == 'mp4' ? (bestAac ?? bestOpus) : (bestOpus ?? bestAac);
      final isH264 = prettyVideoCodec(s.videoCodec) == 'H264';
      final isHighRes = s.videoResolution.height >= 1080;
      options.add(QualityOption(
        kind: QualityKind.videoOnly,
        videoTag: s.tag,
        audioTag: pair?.tag,
        label: _videoLabel(s.qualityLabel, s.videoResolution.height, s.framerate.framesPerSecond.toInt()),
        container: _containerLabel(container, prettyVideoCodec(s.videoCodec)),
        codec: prettyVideoCodec(s.videoCodec),
        fps: s.framerate.framesPerSecond.toInt(),
        sizeBytes: s.size.totalBytes + (pair?.size.totalBytes ?? 0),
        ext: container,
        srcExt: container,
        // Recommend the highest H264/MP4 1080p row: plays everywhere.
        recommended: isH264 && s.videoResolution.height == 1080,
      ));
      // ignore: avoid_redundant_argument_values — isHighRes kept for clarity
      assert(isHighRes || true);
    }

    // Audio-only options: native m4a, native opus, and MP3 conversion.
    if (bestAac != null) {
      options.add(QualityOption(
        kind: QualityKind.audioOnly,
        videoTag: bestAac.tag,
        label: 'M4A ${_audioKbps(bestAac)}kbps',
        container: 'M4A (AAC)',
        codec: 'AAC',
        fps: 0,
        sizeBytes: bestAac.size.totalBytes,
        ext: 'm4a',
        srcExt: 'm4a',
      ));
    }
    if (bestOpus != null) {
      options.add(QualityOption(
        kind: QualityKind.audioOnly,
        videoTag: bestOpus.tag,
        label: 'OPUS ${_audioKbps(bestOpus)}kbps',
        container: 'WEBM (Opus)',
        codec: 'Opus',
        fps: 0,
        sizeBytes: bestOpus.size.totalBytes,
        ext: 'webm',
        srcExt: 'webm',
      ));
    }
    final mp3Source = bestAac ?? bestOpus;
    if (mp3Source != null) {
      final seconds = video.duration?.inSeconds ?? 0;
      options.add(QualityOption(
        kind: QualityKind.audioOnly,
        videoTag: mp3Source.tag,
        label: 'MP3 192kbps',
        container: 'MP3',
        codec: 'MP3',
        fps: 0,
        sizeBytes: seconds > 0 ? (192000 ~/ 8) * seconds : mp3Source.size.totalBytes,
        ext: 'mp3',
        srcExt: mp3Source.container.name == 'mp4' ? 'm4a' : 'webm',
        mp3: true,
      ));
    }

    _optionsCache[video.id.value] = options;
    _manifestCache[video.id.value] = manifest;
    return options;
  }

  /// Resolves the exact streams (by tag) saved on the option at download time.
  static Future<StreamManifest> getManifest(VideoId id) => _yt.videos.streams.getManifest(id);

  /// Resolves the manifest from ONE SPECIFIC YouTube API client.
  ///
  /// Pinning the client matters: the download engine pairs each stream URL
  /// with the User-Agent of the client that minted it. Mismatched fingerprints
  /// (or PO-Token-gated clients like `android`) get HTTP 403 from Google's
  /// video servers.
  static Future<StreamManifest> getManifestWithClient(VideoId id, YoutubeApiClient client) =>
      _yt.videos.streams.getManifest(id, ytClients: [client]);

  static void clearCache() {
    _optionsCache.clear();
    _manifestCache.clear();
  }

  // ---------------- helpers ----------------

  static AudioOnlyStreamInfo? _pickAudio(List<AudioOnlyStreamInfo> sorted, String codecPrefix) {
    for (final a in sorted) {
      if (a.audioCodec.toLowerCase().startsWith(codecPrefix)) return a;
    }
    return null;
  }

  static String _audioKbps(AudioOnlyStreamInfo a) => (a.bitrate.bitsPerSecond / 1000).round().toString();

  static String _videoLabel(String raw, int height, int fps) {
    var label = raw.isNotEmpty ? raw : '${height}p';
    // Append fps suffix only when the label does not already contain it
    // (protects against e.g. "720p50" + "50").
    if (fps >= 50 && !label.endsWith(fps.toString())) {
      label = '$label${fps >= 60 ? 60 : fps}';
    }
    // Friendly marketing labels, SnapTube-style.
    if (height == 2160) label = '$label • 4K';
    if (height == 4320) label = '$label • 8K';
    return label;
  }

  static String _containerLabel(String container, String codec) {
    final c = container.toUpperCase();
    return '$c ($codec)';
  }
}
