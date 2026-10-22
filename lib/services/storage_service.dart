import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/saved_file.dart';

/// Saves finished files to one of the user-chosen locations:
///  • default  — public Downloads/GetTube on the phone (MediaStore on 10+)
///  • sdcard   — public Downloads/GetTube on the SD card (volume-aware)
///  • custom   — any folder the user picked via SAF (incl. SD card)
///  • app      — app-specific directory (private)
/// Also keeps a registry of saved files so the Downloads screen survives
/// app restarts.
class StorageService {
  StorageService._();

  static const MethodChannel _channel = MethodChannel('gettube/storage');
  static const String _registryKey = 'gettube.saved_files';

  // ---------------- destinations ----------------

  /// Moves a finished file to its final destination and returns a SavedFile.
  static Future<SavedFile> publish({
    required String tempPath,
    required String displayName,
    required String mime,
    required String subDir, // StorageDirs.video | StorageDirs.audio
    required String location, // 'default' | 'sdcard' | 'app'
    String? volumeId,
    String? thumbUrl,
  }) async {
    if (location == 'default' || location == 'sdcard') {
      final srcFile = File(tempPath);
      final int sizeBefore = srcFile.existsSync() ? srcFile.lengthSync() : 0;
      try {
        final res = await _channel.invokeMethod('saveFile', {
          'src': tempPath,
          'subDir': subDir,
          'name': displayName,
          'mime': mime,
          'volume': location == 'sdcard' ? (volumeId ?? '') : 'primary',
        });
        final map = Map<String, dynamic>.from(res as Map);
        final path = (map['path'] as String?) ?? '';
        final uri = (map['uri'] as String?) ?? '';
        final label = location == 'sdcard'
            ? 'SD/Download/GetTube/$subDir'
            : 'Download/GetTube/$subDir';
        final saved = SavedFile(
          name: displayName,
          path: path.isNotEmpty ? path : tempPath,
          uri: uri.isNotEmpty ? uri : null,
          sizeBytes: sizeBefore,
          modifiedAt: DateTime.now(),
          isVideo: subDir == StorageDirs.video,
          thumbUrl: thumbUrl,
          folderLabel: label,
        );
        await _register(saved);
        // source already moved by the platform side; best-effort cleanup
        if (srcFile.existsSync()) {
          try {
            srcFile.deleteSync();
          } catch (_) {}
        }
        return saved;
      } catch (_) {
        // fall back to app-private storage below
      }
    }

    // App-specific external dir — visible in Files app, no permission needed.
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/GetTube/$subDir');
    await dir.create(recursive: true);
    final dest = _uniqueFile(dir, displayName);
    await File(tempPath).copy(dest.path);
    final src = File(tempPath);
    if (src.existsSync()) {
      try {
        src.deleteSync();
      } catch (_) {}
    }
    final saved = SavedFile(
      name: displayName,
      path: dest.path,
      sizeBytes: dest.lengthSync(),
      modifiedAt: File(dest.path).lastModifiedSync(),
      isVideo: subDir == StorageDirs.video,
      thumbUrl: thumbUrl,
      folderLabel: 'GetTube/$subDir',
    );
    await _register(saved);
    return saved;
  }

  /// Copies a finished file into a user-picked SAF folder (custom location).
  static Future<SavedFile> publishToTree({
    required String tempPath,
    required String treeUri,
    required String displayName,
    required String mime,
    String? thumbUrl,
  }) async {
    final srcFile = File(tempPath);
    final int size = srcFile.existsSync() ? srcFile.lengthSync() : 0;
    final res = await _channel.invokeMethod('saveFileToTree', {
      'src': tempPath,
      'tree': treeUri,
      'name': displayName,
      'mime': mime,
    });
    final map = Map<String, dynamic>.from(res as Map);
    final saved = SavedFile(
      name: (map['name'] as String?) ?? displayName,
      path: '',
      uri: map['uri'] as String?,
      sizeBytes: size,
      modifiedAt: DateTime.now(),
      isVideo: mime.startsWith('video'),
      thumbUrl: thumbUrl,
      folderLabel: (map['folder'] as String?) ?? '',
    );
    await _register(saved);
    if (srcFile.existsSync()) {
      try {
        srcFile.deleteSync();
      } catch (_) {}
    }
    return saved;
  }

  static File _uniqueFile(Directory dir, String name) {
    var out = File('${dir.path}/$name');
    int i = 1;
    while (out.existsSync()) {
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      out = File('${dir.path}/$base ($i)$ext');
      i++;
    }
    return out;
  }

  // ---------------- volumes / folders / network ----------------

  /// Available storage volumes: [{id, removable, root}].
  static Future<List<Map<String, dynamic>>> getVolumes() async {
    try {
      final res = await _channel.invokeMethod('getStorageInfo');
      return List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } catch (_) {
      return [];
    }
  }

  /// Opens the SAF directory picker. Returns {uri, name} or null (canceled).
  static Future<Map<String, String>?> pickFolder() async {
    try {
      final res = await _channel.invokeMethod('pickFolder');
      if (res == null) return null;
      return Map<String, String>.from(res as Map);
    } catch (_) {
      return null;
    }
  }

  /// Creates a subfolder inside [treeUri] and returns {uri, name} for it.
  static Future<Map<String, String>?> createFolder(String treeUri, String name) async {
    try {
      final res = await _channel.invokeMethod('createFolder', {'tree': treeUri, 'name': name});
      if (res == null) return null;
      return Map<String, String>.from(res as Map);
    } catch (_) {
      return null;
    }
  }

  /// Opens a content:// file with a viewer app.
  static Future<bool> openTarget(String uri, String mime) async {
    try {
      final res = await _channel.invokeMethod('openFile', {'target': uri, 'mime': mime});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Shares a content:// file.
  static Future<bool> shareTarget(String uri, String mime, {String title = 'GetTube'}) async {
    try {
      final res = await _channel.invokeMethod(
        'shareFile',
        {'target': uri, 'mime': mime, 'title': title},
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the containing folder in the system Files app.
  static Future<bool> openFolder(String target) async {
    try {
      final res = await _channel.invokeMethod('openFolder', {'target': target});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// True when the active network is metered (mobile data).
  static Future<bool> isMetered() async {
    try {
      final res = await _channel.invokeMethod('networkInfo');
      return (res as Map)['metered'] == true;
    } catch (_) {
      return false;
    }
  }

  // ---------------- Registry ----------------

  static Future<void> _register(SavedFile f) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_registryKey) ?? [];
    list.add(jsonEncode({
      'name': f.name,
      'path': f.path,
      'uri': f.uri ?? '',
      'size': f.sizeBytes,
      'date': f.modifiedAt.millisecondsSinceEpoch,
      'video': f.isVideo,
      'thumb': f.thumbUrl ?? '',
      'folder': f.folderLabel,
    }));
    // keep the last 300 entries
    final trimmed = list.length > 300 ? list.sublist(list.length - 300) : list;
    await prefs.setStringList(_registryKey, trimmed);
  }

  static Future<List<SavedFile>> listSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_registryKey) ?? [];
    final out = <SavedFile>[];
    for (final raw in list.reversed) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final path = m['path'] as String? ?? '';
        final uri = m['uri'] as String? ?? '';
        if (path.isEmpty && uri.isEmpty) continue;
        // Drop entries deleted outside the app (best effort for app-dir files)
        int size = (m['size'] as num?)?.toInt() ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0);
        if (path.isNotEmpty && !uri.startsWith('content://') && File(path).existsSync()) {
          size = File(path).lengthSync();
          date = File(path).lastModifiedSync();
        }
        out.add(SavedFile(
          name: m['name'] as String? ?? 'file',
          path: path,
          uri: uri.isEmpty ? null : uri,
          sizeBytes: size,
          modifiedAt: date,
          isVideo: m['video'] as bool? ?? false,
          thumbUrl: (m['thumb'] as String?)?.isEmpty == true ? null : m['thumb'] as String?,
          folderLabel: m['folder'] as String? ?? '',
        ));
      } catch (_) {
        // skip corrupted entry
      }
    }
    return out;
  }

  static Future<bool> deleteSaved(SavedFile f) async {
    var ok = false;
    try {
      if (f.uri != null && f.uri!.startsWith('content://')) {
        await _channel.invokeMethod('deleteSaved', {'target': f.uri});
        ok = true;
      } else {
        final file = File(f.path);
        if (file.existsSync()) {
          file.deleteSync();
          ok = true;
        } else {
          ok = true; // already gone
        }
      }
    } catch (_) {
      ok = false;
    }
    // remove from registry either way
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_registryKey) ?? [];
    final filtered = list.where((raw) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        return m['path'] != f.path && m['uri'] != (f.uri ?? '');
      } catch (_) {
        return true;
      }
    }).toList();
    await prefs.setStringList(_registryKey, filtered);
    return ok;
  }

  /// Removes *.part leftovers and temp outputs from aborted runs.
  static Future<void> clearTemps() async {
    try {
      final tmp = await getTemporaryDirectory();
      final dl = Directory('${tmp.path}/dl');
      if (dl.existsSync()) {
        dl.deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  static String mimeFor(String ext, bool isVideo) {
    switch (ext.toLowerCase()) {
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return isVideo ? 'video/webm' : 'audio/webm';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      default:
        return isVideo ? 'video/*' : 'audio/*';
    }
  }
}
