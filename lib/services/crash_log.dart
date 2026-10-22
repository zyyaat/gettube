import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lightweight, never-throwing crash/diagnostic log.
///
/// Every uncaught error (boot failure, zone error, widget build error,
/// platform dispatcher error) is appended here so problems on real devices
/// can be diagnosed WITHOUT adb. The user can view & copy the log from
/// Settings → Diagnostics and share it for a fast fix.
class CrashLog {
  CrashLog._();

  static const int maxEntries = 250;
  static final List<String> _entries = [];
  static bool _dirty = false;
  static Timer? _flushTimer;
  static String? _cachedPath;

  /// In-memory entries (also used as fallback if file IO is unavailable).
  static List<String> get entries => List.unmodifiable(_entries);

  /// Records an error. NEVER throws — this must be safe to call from any
  /// error handler, even before the Flutter binding is ready.
  static void write(String message, [StackTrace? stack]) {
    try {
      final ts = DateTime.now().toIso8601String();
      final st = stack == null
          ? ''
          : '\n${stack.toString().split('\n').take(6).join('\n')}';
      _entries.add('[$ts] $message$st');
      if (_entries.length > maxEntries) {
        _entries.removeRange(0, _entries.length - maxEntries);
      }
      _dirty = true;
      _scheduleFlush();
    } catch (_) {
      // Swallow: logging must never crash the app.
    }
  }

  static void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 2), _flush);
  }

  static Future<void> _flush() async {
    _flushTimer = null;
    if (!_dirty) return;
    _dirty = false;
    try {
      final f = await _file();
      if (f != null) {
        await f.writeAsString('${_entries.join('\n\n')}\n', flush: false);
      }
    } catch (_) {}
  }

  static Future<File?> _file() async {
    try {
      if (_cachedPath != null) return File(_cachedPath!);
      final dir = await getApplicationDocumentsDirectory();
      _cachedPath = '${dir.path}/gettube_diagnostics.log';
      return File(_cachedPath!);
    } catch (_) {
      return null;
    }
  }

  /// Full log text (file content if available, memory buffer otherwise).
  static Future<String> readAll() async {
    try {
      final f = await _file();
      if (f != null && f.existsSync()) {
        final onDisk = await f.readAsString();
        if (onDisk.trim().isNotEmpty) return onDisk;
      }
    } catch (_) {}
    if (_entries.isEmpty) return '';
    return _entries.join('\n\n');
  }

  static Future<void> clear() async {
    try {
      _entries.clear();
      final f = await _file();
      if (f != null && f.existsSync()) {
        await f.writeAsString('');
      }
    } catch (_) {}
  }
}
