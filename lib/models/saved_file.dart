/// A file that was successfully saved on the device.
class SavedFile {
  SavedFile({
    required this.name,
    required this.path,
    this.uri,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.isVideo,
    this.thumbUrl,
    this.folderLabel = '',
  });

  final String name;
  final String path; // openable path (app dir or MediaStore DATA path)
  final String? uri; // MediaStore / SAF content uri (public & custom saves)
  final int sizeBytes;
  final DateTime modifiedAt;
  final bool isVideo;

  /// Source YouTube thumbnail (for the SnapTube-style library view).
  /// Older registry entries may not have it -> null -> icon fallback.
  final String? thumbUrl;

  /// Human-friendly location of the file, e.g. "Download/GetTube/Video"
  /// or the picked custom folder name. Empty on older entries.
  final String folderLabel;
}
