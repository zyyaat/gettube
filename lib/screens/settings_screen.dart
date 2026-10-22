import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/i18n.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../state/settings_controller.dart';
import 'diagnostics_screen.dart';

/// Professional, tabbed settings:
///  عام        — language, theme, notifications
///  التنزيلات  — simultaneous downloads (1..10), mobile data gate
///  التخزين    — save location: phone / SD card / custom folder / app
///  حول        — version + report a problem (no repo talk)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L.settings),
          bottom: TabBar(
            tabs: [
              Tab(text: L.tabGeneral),
              Tab(text: L.tabDownloads),
              Tab(text: L.tabStorage),
              Tab(text: L.tabAbout),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _GeneralTab(),
            _DownloadsTab(),
            _StorageTab(),
            _AboutTab(),
          ],
        ),
      ),
    );
  }
}

/// A rounded, grouped card of settings rows.
class _Group extends StatelessWidget {
  const _Group({required this.children, this.footer});

  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Column(children: rows),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              footer!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            ),
          ),
      ],
    );
  }
}

Widget _tabTitle(BuildContext context, String text) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
    child: Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    ),
  );
}

// ---------------- General ----------------

class _GeneralTab extends StatelessWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return ListView(
      children: [
        _tabTitle(context, L.appearance),
        _Group(
          children: [
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: Text(L.language),
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
                  ButtonSegment(value: 'system', icon: const Icon(Icons.settings_suggest_outlined, size: 18), label: Text(L.themeSystem)),
                  ButtonSegment(value: 'light', icon: const Icon(Icons.light_mode_outlined, size: 18), label: Text(L.themeLight)),
                  ButtonSegment(value: 'dark', icon: const Icon(Icons.dark_mode_outlined, size: 18), label: Text(L.themeDark)),
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
          ],
        ),
        _tabTitle(context, L.notifications),
        _Group(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: Text(L.notifications),
              value: s.notifications,
              onChanged: (v) => s.setNotifications(v),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Downloads ----------------

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.watch<SettingsController>();
    return ListView(
      children: [
        _tabTitle(context, L.tabDownloads),
        _Group(
          children: [
            ListTile(
              leading: const Icon(Icons.bolt_rounded),
              title: Text(L.maxTasks),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.maxTasksHint, style: theme.textTheme.bodySmall),
                  Slider(
                    value: s.maxConcurrent.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${s.maxConcurrent}',
                    onChanged: (v) => s.setMaxConcurrent(v.round()),
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${s.maxConcurrent}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.signal_cellular_alt_rounded),
              title: Text(L.mobileData),
              subtitle: Text(L.mobileDataHint),
              value: s.mobileDataAllowed,
              onChanged: (v) => s.setMobileDataAllowed(v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _Group(
          children: [
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: Text(L.clearCache),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await StorageService.clearTemps();
                messenger.showSnackBar(SnackBar(content: Text(L.cacheCleared)));
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Storage ----------------

class _StorageTab extends StatefulWidget {
  const _StorageTab();

  @override
  State<_StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends State<_StorageTab> {
  bool _hasSd = false;
  String? _sdVolumeId;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadVolumes();
  }

  Future<void> _loadVolumes() async {
    final volumes = await StorageService.getVolumes();
    if (!mounted) return;
    String? sd;
    for (final v in volumes) {
      if (v['removable'] == true) {
        sd = v['id'] as String?;
        break;
      }
    }
    setState(() {
      _sdVolumeId = sd;
      _hasSd = sd != null;
      _loaded = true;
    });
    // keep the engine's volume id in sync with the physical card
    final s = context.read<SettingsController>();
    if (_hasSd && s.saveLocation == 'sdcard' && s.sdVolumeId != sd) {
      await s.setSdVolumeId(sd!);
    }
  }

  Future<void> _onSelect(String value) async {
    final s = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);
    if (value == 'custom') {
      final picked = await StorageService.pickFolder();
      if (!mounted) return;
      if (picked == null) {
        setState(() {}); // canceled — keep the previous selection
        return;
      }
      await s.setCustomFolder(picked['uri'] ?? '', picked['name'] ?? '');
      await s.setSaveLocation('custom');
      messenger.showSnackBar(SnackBar(content: Text(L.locationChanged)));
    } else {
      if (value == 'sdcard') {
        if (!_hasSd) {
          messenger.showSnackBar(SnackBar(content: Text(L.noSdCard)));
          return;
        }
        if (_sdVolumeId != null) await s.setSdVolumeId(_sdVolumeId!);
      }
      await s.setSaveLocation(value);
      if (mounted) setState(() {});
    }
  }

  Future<void> _createFolder() async {
    final s = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);
    if (s.customTreeUri == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.newFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: L.folderName),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.cancel)),
          FilledButton(
            onPressed: () {
              final n = controller.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, n);
            },
            child: Text(L.newFolder),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final res = await StorageService.createFolder(s.customTreeUri!, name);
    if (!mounted) return;
    if (res != null) {
      await s.setCustomFolder(res['uri'] ?? '', res['name'] ?? name);
      messenger.showSnackBar(SnackBar(content: Text(L.folderCreated)));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(L.folderCreateFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.watch<SettingsController>();
    return ListView(
      children: [
        _tabTitle(context, L.saveLocation),
        _Group(
          footer: L.saveLocationHint,
          children: [
            RadioGroup<String>(
              groupValue: s.saveLocation,
              onChanged: (v) {
                if (v != null) _onSelect(v);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    secondary: const Icon(Icons.phone_android_rounded),
                    title: Text(L.phoneStorage),
                    subtitle: const Text('Download/GetTube'),
                    value: 'default',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile<String>(
                    secondary: const Icon(Icons.sd_card_outlined),
                    title: Text(L.sdCard),
                    subtitle: Text(_hasSd ? 'Download/GetTube' : L.noSdCard),
                    value: 'sdcard',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile<String>(
                    secondary: const Icon(Icons.folder_open_rounded),
                    title: Text(L.customFolder),
                    subtitle: Text(
                      s.saveLocation == 'custom' && s.customFolderLabel.isNotEmpty
                          ? s.customFolderLabel
                          : L.customFolderHint,
                    ),
                    value: 'custom',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile<String>(
                    secondary: const Icon(Icons.lock_outline_rounded),
                    title: Text(L.appPrivate),
                    subtitle: Text(L.appPrivateHint),
                    value: 'app',
                  ),
                ],
              ),
            ),
          ],
        ),
        if (s.saveLocation == 'custom' && s.customTreeUri != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: Text(L.chooseAnotherFolder, overflow: TextOverflow.ellipsis),
                    onPressed: () => _onSelect('custom'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: Text(L.newFolder, overflow: TextOverflow.ellipsis),
                    onPressed: _createFolder,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!_loaded)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (_hasSd && s.saveLocation == 'sdcard')
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Download/GetTube',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------- About ----------------

class _AboutTab extends StatefulWidget {
  const _AboutTab();

  @override
  State<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<_AboutTab> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    UpdateInfo? found;
    try {
      found = await UpdateService.check();
    } catch (_) {
      found = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.updateCheckFailed)));
      setState(() => _checking = false);
      return;
    }
    if (!mounted) return;
    setState(() => _checking = false);
    if (found != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.updateFound(found.version))));
      try {
        await launchUrl(Uri.parse(found.apkUrl), mode: LaunchMode.externalApplication);
      } catch (_) {
        try {
          await launchUrl(Uri.parse(found.releaseUrl), mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L.updateIsLatest(AppMeta.version))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 24),
        Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.seed, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.download_rounded, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 12),
            Text('GetTube', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text('${L.versionLabel} ${AppMeta.version}', style: theme.textTheme.bodySmall),
          ],
        ),
        _tabTitle(context, L.about),
        _Group(
          children: [
            ListTile(
              leading: _checking
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.system_update_rounded),
              title: Text(_checking ? L.checkingForUpdates : L.checkForUpdates),
              subtitle: Text(L.updateBannerHint),
              onTap: _checking ? null : _check,
            ),
          ],
        ),
        _Group(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Text(
                L.aboutText,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.7, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        _tabTitle(context, L.reportProblem),
        _Group(
          footer: L.reportProblemHint,
          children: [
            ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: Text(L.reportProblem),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
