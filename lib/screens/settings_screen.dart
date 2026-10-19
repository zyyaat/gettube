import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/i18n.dart';
import 'diagnostics_screen.dart';
import '../services/storage_service.dart';
import '../state/settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text(L.settings)),
      body: ListView(
        children: [
          _sectionTitle(context, L.appearance),

          // Language
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(L.language),
            subtitle: Text(s.lang.displayName),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ar', label: Text('عربي')),
                ButtonSegment(value: 'en', label: Text('EN')),
              ],
              selected: {s.lang.code},
              onSelectionChanged: (sel) {
                s.setLang(sel.first == 'ar' ? AppLang.arabic : AppLang.english);
              },
            ),
          ),

          // Theme
          ListTile(
            leading: const Icon(Icons.brightness_6_rounded),
            title: Text(L.theme),
            subtitle: Text(
              s.themeMode == ThemeMode.system
                  ? L.themeSystem
                  : s.themeMode == ThemeMode.light
                      ? L.themeLight
                      : L.themeDark,
            ),
            trailing: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'system', icon: const Icon(Icons.settings_suggest_outlined), label: Text(L.themeSystem)),
                ButtonSegment(value: 'light', icon: const Icon(Icons.light_mode_outlined), label: Text(L.themeLight)),
                ButtonSegment(value: 'dark', icon: const Icon(Icons.dark_mode_outlined), label: Text(L.themeDark)),
              ],
              selected: {
                s.themeMode == ThemeMode.system
                    ? 'system'
                    : s.themeMode == ThemeMode.light
                        ? 'light'
                        : 'dark'
              },
              onSelectionChanged: (sel) {
                s.setThemeMode(
                  sel.first == 'system'
                      ? ThemeMode.system
                      : sel.first == 'light'
                          ? ThemeMode.light
                          : ThemeMode.dark,
                );
              },
            ),
          ),

          _sectionTitle(context, L.downloadEngine),

          // Parallel downloads
          ListTile(
            leading: const Icon(Icons.account_tree_rounded),
            title: Text(L.parallelDownloads),
            subtitle: Slider(
              value: s.maxConcurrent.toDouble(),
              min: 1,
              max: 4,
              divisions: 3,
              label: '${s.maxConcurrent}',
              onChanged: (v) => s.setMaxConcurrent(v.round()),
            ),
            trailing: Text('${s.maxConcurrent}', style: theme.textTheme.titleMedium),
          ),

          // Public saving
          SwitchListTile(
            secondary: const Icon(Icons.folder_shared_rounded),
            title: Text(L.savePublic),
            subtitle: Text(L.savePublicHint),
            value: s.savePublic,
            onChanged: (v) => s.setSavePublic(v),
          ),

          // Notifications
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(L.notifications),
            value: s.notifications,
            onChanged: (v) => s.setNotifications(v),
          ),

          // Clear cache
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(L.clearCache),
            onTap: () async {
              await StorageService.clearTemps();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.cacheCleared)));
              }
            },
          ),

          _sectionTitle(context, L.diagnostics),

          // Error log — lets the user report problems without adb
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(L.errorLog),
            subtitle: Text(L.errorLogHint),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),

          _sectionTitle(context, L.about),

          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: Text(L.projectOnGithub),
            subtitle: const Text(AppMeta.repoUrl),
            onTap: () async {
              final uri = Uri.parse(AppMeta.repoUrl);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text(
              '${L.appName} v${AppMeta.version}\n${L.aboutText}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
