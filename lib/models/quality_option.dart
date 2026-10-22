/// Describes one downloadable option for a video (a quality row in the sheet).
enum QualityKind { muxed, videoOnly, audioOnly }

class QualityOption {
  const QualityOption({
    required this.kind,
    required this.videoTag,
    this.audioTag,
    required this.label,
    required this.container,
    required this.codec,
    required this.fps,
    required this.sizeBytes,
    required this.ext,
    required this.srcExt,
    this.mp3 = false,
    this.recommended = false,
  });

  /// muxed = video+audio in one stream (instant, limited by YouTube).
  /// videoOnly = high quality stream that will be muxed with best audio by FFmpeg.
  /// audioOnly = audio stream (m4a/opus or converted to mp3).
  final QualityKind kind;

  /// YouTube stream tag of the video (or audio) stream to download.
  final int videoTag;

  /// Tag of the paired audio stream (videoOnly only).
  final int? audioTag;

  /// Human label, e.g. "1080p60", "4K", "MP3 192kbps".
  final String label;

  /// Container/codec family label, e.g. "MP4 (H264)".
  final String container;
  final String codec;
  final int fps;

  /// Estimated final size in bytes (video + audio when muxing).
  final int sizeBytes;

  /// Final file extension after processing ("mp4", "webm", "m4a", "mp3").
  final String ext;

  /// Extension of the raw downloaded stream before processing.
  final String srcExt;

  /// True for MP3 conversion entries (audioOnly).
  final bool mp3;

  final bool recommended;

  bool get needsMux => kind == QualityKind.videoOnly;
}

/// Friendly codec names.
String prettyVideoCodec(String raw) {
  final c = raw.toLowerCase();
  if (c.startsWith('avc1') || c.startsWith('h264')) return 'H264';
  if (c.startsWith('vp09') || c.startsWith('vp9')) return 'VP9';
  if (c.startsWith('av01') || c.startsWith('av1')) return 'AV1';
  if (c.startsWith('vp8')) return 'VP8';
  if (c.startsWith('h263')) return 'H263';
  if (c.startsWith('mp4v')) return 'MPEG4';
  return raw.toUpperCase();
}

String prettyAudioCodec(String raw) {
  final c = raw.toLowerCase();
  if (c.startsWith('mp4a')) return 'AAC';
  if (c.startsWith('opus')) return 'Opus';
  if (c.startsWith('vorbis')) return 'Vorbis';
  if (c.startsWith('ec-3')) return 'EAC3';
  if (c.startsWith('mp3')) return 'MP3';
  return raw.toUpperCase();
}
