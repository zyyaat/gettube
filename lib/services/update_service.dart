import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/constants.dart';

/// A newer release found on GitHub.
class UpdateInfo {
  final String tag; // e.g. "build-22"
  final int buildNumber; // 22
  final String version; // e.g. "1.0.11" (from the release name/notes)
  final String apkUrl; // direct download link to GetTube-universal-rN.apk
  final String releaseUrl;

  const UpdateInfo({
    required this.tag,
    required this.buildNumber,
    required this.version,
    required this.apkUrl,
    required this.releaseUrl,
  });
}

/// Checks GitHub for a newer published release and returns it.
///
/// GetTube is distributed outside any store, so the ONLY way users ever learn
/// a new version exists is this in-app check (SnapTube pushes updates from
/// its store; we replicate that with a GitHub releases check).
/// The GitHub API is public — no token, 60 requests/hour per IP is plenty.
class UpdateService {
  UpdateService._();

  /// This build's number — bump together with the `build-N` tag.
  static int get currentBuild => AppMeta.buildTag;

  static const String _repo = 'zyyaat/gettube';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Latest published release, or null when this build is already the
  /// newest one. Throws on network failure — the home banner swallows that
  /// silently, the settings button shows a friendly message instead.
  static Future<UpdateInfo?> check() async {
    final res = await _dio.get<String>(
      'https://api.github.com/repos/$_repo/releases/latest',
      options: Options(headers: {
        'accept': 'application/vnd.github+json',
        'user-agent': 'GetTube-App',
      }),
    );
    if (res.data == null) return null;
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(res.data!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final tag = (json['tag_name'] ?? '').toString(); // "build-22"
    final m = RegExp(r'build-(\d+)').firstMatch(tag);
    if (m == null) return null;
    final latest = int.parse(m.group(1)!);
    if (latest <= currentBuild) return null;

    String? apkUrl;
    final assets = (json['assets'] as List?) ?? const [];
    for (final a in assets) {
      final name = (a['name'] ?? '').toString();
      final url = (a['browser_download_url'] ?? '').toString();
      if (url.isEmpty) continue;
      // Prefer the universal APK (arm32 + arm64 + x86_64).
      if (name.contains('universal') || name.endsWith('.apk')) {
        apkUrl = url;
        if (name.contains('universal')) break;
      }
    }
    final releaseUrl =
        (json['html_url'] ?? 'https://github.com/$_repo/releases/latest').toString();
    return UpdateInfo(
      tag: tag,
      buildNumber: latest,
      version: _versionFromNotes(json),
      apkUrl: (apkUrl != null && apkUrl.isNotEmpty) ? apkUrl : releaseUrl,
      releaseUrl: releaseUrl,
    );
  }

  /// Pulls "1.0.11" out of the release name/notes if present.
  static String _versionFromNotes(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString();
    final body = (json['body'] ?? '').toString();
    for (final s in [name, body]) {
      final m = RegExp(r'1\.\d+\.\d+').firstMatch(s);
      if (m != null) return m.group(0)!;
    }
    return '';
  }
}
