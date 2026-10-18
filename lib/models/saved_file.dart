/// A file that was successfully saved on the device.
class SavedFile {
  SavedFile({
    required this.name,
    required this.path,
    this.uri,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.isVideo,
  });

  final String name;
  final String path; // openable path (app dir or MediaStore DATA path)
  final String? uri; // MediaStore content uri (public saves on Android 10+)
  final int sizeBytes;
  final DateTime modifiedAt;
  final bool isVideo;
}
