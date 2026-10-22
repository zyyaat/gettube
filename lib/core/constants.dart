import 'package:flutter/material.dart';

/// Brand colors for GetTube.
class AppColors {
  AppColors._();

  static const Color seed = Color(0xFF7C4DFF); // deep violet
  static const Color accent = Color(0xFF00E5FF); // cyan accent
  static const Color success = Color(0xFF00C853);
  static const Color danger = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFAB00);
}

/// App metadata.
/// ⚠️ Keep [version] and [buildTag] in sync with pubspec.yaml (`1.0.11+12`)
/// and the CI tag (`build-22`) — UpdateService compares [buildTag] against
/// the newest GitHub tag to tell users an update exists.
class AppMeta {
  AppMeta._();

  static const String name = 'GetTube';
  static const String version = '1.0.11';
  static const int buildTag = 22;
}

/// Sub-directories used to organize saved media.
class StorageDirs {
  StorageDirs._();

  static const String video = 'Video';
  static const String audio = 'Audio';
}
