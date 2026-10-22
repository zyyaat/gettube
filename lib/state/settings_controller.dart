import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';
import '../services/download_manager.dart';

/// Global app settings persisted in SharedPreferences.
class SettingsController extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.dark;
  AppLang lang = AppLang.arabic;
  int maxConcurrent = 2;
  bool notifications = true;
  bool _seenDisclaimer = false;

  /// Where downloads are saved: 'default' (public Downloads on the phone),
  /// 'sdcard' (public Downloads on the SD card), 'custom' (user-picked SAF
  /// folder), 'app' (app-private directory).
  String saveLocation = 'default';
  String? sdVolumeId;
  String? customTreeUri;
  String customFolderLabel = '';

  /// Allow downloads over mobile data (when false: wait for Wi-Fi).
  bool mobileDataAllowed = true;

  bool get seenDisclaimer => _seenDisclaimer;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[prefs.getInt('theme') ?? ThemeMode.dark.index];
    lang = (prefs.getInt('lang') ?? 0) == 0 ? AppLang.arabic : AppLang.english;
    maxConcurrent = prefs.getInt('parallel') ?? 2;
    // migrate the old single "public" toggle to the new location model
    saveLocation = prefs.getString('saveLocation') ??
        ((prefs.getBool('public') ?? true) ? 'default' : 'app');
    sdVolumeId = prefs.getString('sdVolume');
    customTreeUri = prefs.getString('customTree');
    customFolderLabel = prefs.getString('customFolderLabel') ?? '';
    mobileDataAllowed = prefs.getBool('mobileData') ?? true;
    notifications = prefs.getBool('notify') ?? true;
    _seenDisclaimer = prefs.getBool('disclaimer') ?? false;
    L.lang = lang;
    _applyToEngine();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme', m.index);
    notifyListeners();
  }

  Future<void> setLang(AppLang l) async {
    lang = l;
    L.lang = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lang', l == AppLang.arabic ? 0 : 1);
    notifyListeners();
  }

  Future<void> setMaxConcurrent(int n) async {
    maxConcurrent = n.clamp(1, 10);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('parallel', maxConcurrent);
    _applyToEngine();
    notifyListeners();
  }

  Future<void> setSaveLocation(String v) async {
    saveLocation = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saveLocation', v);
    _applyToEngine();
    notifyListeners();
  }

  Future<void> setSdVolumeId(String id) async {
    sdVolumeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sdVolume', id);
    _applyToEngine();
    notifyListeners();
  }

  Future<void> setCustomFolder(String uri, String label) async {
    customTreeUri = uri;
    customFolderLabel = label;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customTree', uri);
    await prefs.setString('customFolderLabel', label);
    _applyToEngine();
    notifyListeners();
  }

  Future<void> setMobileDataAllowed(bool v) async {
    mobileDataAllowed = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mobileData', v);
    _applyToEngine();
    notifyListeners();
  }

  Future<void> setNotifications(bool v) async {
    notifications = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify', v);
    notifyListeners();
  }

  Future<void> acknowledgeDisclaimer() async {
    _seenDisclaimer = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disclaimer', true);
    notifyListeners();
  }

  void _applyToEngine() {
    DownloadManager.instance
      ..maxConcurrent = maxConcurrent
      ..saveLocation = saveLocation
      ..sdVolumeId = sdVolumeId
      ..customTreeUri = customTreeUri
      ..customFolderLabel = customFolderLabel
      ..mobileDataAllowed = mobileDataAllowed;
  }
}
