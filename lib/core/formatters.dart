/// Pure formatting helpers (bytes, durations, counts, speeds).
/// Hand-rolled to avoid pulling in `intl` for a handful of functions.

String formatBytes(num bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double v = bytes.toDouble();
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final String str = (i == 0 || v >= 100) ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$str ${units[i]}';
}

String formatSpeed(double bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final int h = d.inHours;
  final String mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final String ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '${d.inMinutes}:$ss';
}

/// 1234 -> 1.2K, 5600000 -> 5.6M ...
String formatCount(num n) {
  if (n >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1)}B';
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n.toString();
}

/// Removes characters that are illegal in file names on Android.
String sanitizeFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final String trimmed = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  return trimmed.isEmpty ? 'video' : trimmed;
}
