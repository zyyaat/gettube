import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';
import '../services/download_manager.dart';

/// Global app settings persisted in SharedPreferences.
class SettingsController extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.dark;
  AppLang lang = AppLang.arabic;
  int maxConcurrent = 2;
  bool savePublic = true;
  bool notifications = true;
  bool _seenDisclaimer = false;

  bool get seenDisclaimer => _seenDisclaimer;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[prefs.getInt('theme') ?? ThemeMode.dark.index];
    lang = (prefs.getInt('lang') ?? 0) == 0 ? AppLang.arabic : AppLang.english;
    maxConcurrent = prefs.getInt('parallel') ?? 2;
    savePublic = prefs.getBool('public') ?? true;
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
    maxConcurrent = n.clamp(1, 4);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('parallel', maxConcurrent);
    _applyToEngine();
    notifyListeners();
  }

  Future<void> setSavePublic(bool v) async {
    savePublic = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('public', v);
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
      ..savePublic = savePublic;
  }
}
