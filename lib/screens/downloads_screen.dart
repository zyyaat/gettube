import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/i18n.dart';
import '../models/download_task.dart';
import '../models/saved_file.dart';
import '../services/download_manager.dart';
import '../services/storage_service.dart';
import '../widgets/download_tile.dart';

/// SnapTube-style download library:
///  • gradient storage summary (files + size + video/audio counts)
///  • tabs: All / Videos / Music
///  • in-library search + sorting (newest / largest / name)
///  • long-press MULTI-SELECT with batch share & batch delete
///  • per-file menu: open, share, details, delete
///  • live download queue stays pinned on top
enum _Tab { all, video, audio }
enum _Sort { newest, largest, name }

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<SavedFile> _saved = [];
  bool _loadingSaved = true;

  _Tab _tab = _Tab.all;
  _Sort _sort = _Sort.newest;
  bool _searching = false;
  String _query = '';

  final Set<String> _selected = {}; // SavedFile.path

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _refreshSaved();
  }

  Future<void> _refreshSaved() async {
    final files = await StorageService.listSaved();
    if (!mounted) return;
    setState(() {
      _saved = files;
      _loadingSaved = false;
      _selected.removeWhere((p) => !files.any((f) => f.path == p));
    });
  }

  List<SavedFile> get _filtered {
    final q = _query.toLowerCase();
    final list = _saved.where((f) {
      if (_tab == _Tab.video && !f.isVideo) return false;
      if (_tab == _Tab.audio && f.isVideo) return false;
      if (q.isNotEmpty && !f.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      case _Sort.largest:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case _Sort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  // ---------------- actions ----------------

  String _mimeOf(SavedFile f) {
    final dot = f.name.lastIndexOf('.');
    final ext = dot > 0 ? f.name.substring(dot + 1) : '';
    return StorageService.mimeFor(ext, f.isVideo);
  }

  Future<void> _open(SavedFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    // Custom-folder saves live behind content:// URIs — open via platform.
    if (f.uri != null && f.uri!.startsWith('content://')) {
      final ok = await StorageService.openTarget(f.uri!, _mimeOf(f));
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(L.fileMissing)));
      return;
    }
    if (f.path.isEmpty || !File(f.path).existsSync()) {
      messenger.showSnackBar(SnackBar(content: Text(L.fileMissing)));
      return;
    }
    final res = await OpenFilex.open(f.path);
    if (res.type != ResultType.done) {
      messenger.showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  Future<void> _openLocation(SavedFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    final target = (f.uri != null && f.uri!.startsWith('content://')) ? f.uri! : f.path;
    if (target.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(L.fileMissing)));
      return;
    }
    final ok = await StorageService.openFolder(target);
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(L.folderOpenFailed)));
  }

  Future<void> _share(List<SavedFile> files) async {
    final messenger = ScaffoldMessenger.of(context);
    // content:// files (custom folder) go through the platform share sheet.
    final contentFiles = files.where((f) => f.uri != null && f.uri!.startsWith('content://')).toList();
    if (contentFiles.isNotEmpty && contentFiles.length == files.length) {
      var anyOk = false;
      for (final f in contentFiles) {
        if (await StorageService.shareTarget(f.uri!, _mimeOf(f), title: f.name)) anyOk = true;
      }
      if (!anyOk) messenger.showSnackBar(SnackBar(content: Text(L.shareFailed)));
      return;
    }
    final existing = files.where((f) => f.path.isNotEmpty && File(f.path).existsSync()).toList();
    if (existing.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(L.fileMissing)));
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(files: existing.map((f) => XFile(f.path)).toList()),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(L.shareFailed)));
    }
  }

  Future<void> _deleteBatch(List<SavedFile> files) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.delete),
        content: Text(L.deleteConfirm(files.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var ok = 0;
    for (final f in files) {
      if (await StorageService.deleteSaved(f)) ok++;
    }
    await _refreshSaved();
    setState(_selected.clear);
    messenger.showSnackBar(SnackBar(content: Text(L.deletedCount(ok))));
  }

  Future<void> _deleteOne(SavedFile f) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.delete),
        content: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await StorageService.deleteSaved(f);
    await _refreshSaved();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.fileDeleted)));
  }

  void _showDetails(SavedFile f) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.details),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow(L.fileSize, formatBytes(f.sizeBytes)),
            _detailRow(L.fileDate, '${f.modifiedAt.year}/${f.modifiedAt.month}/${f.modifiedAt.day}'),
            _detailRow(L.tabVideos, f.isVideo ? '✓' : '—'),
            _detailRow(L.tabMusic, f.isVideo ? '—' : '✓'),
            const SizedBox(height: 8),
            Text(L.filePath, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 2),
            SelectableText(f.path, style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: f.path));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.logCopied)));
            },
            child: Text(L.copyError),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(L.ok)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  void _toggleSelect(SavedFile f) {
    setState(() {
      if (!_selected.add(f.path)) _selected.remove(f.path);
    });
  }

  void _showFileMenu(SavedFile f) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(L.open),
              onTap: () {
                Navigator.pop(ctx);
                _open(f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(L.share),
              onTap: () {
                Navigator.pop(ctx);
                _share([f]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: Text(L.openFolderMenu),
              onTap: () {
                Navigator.pop(ctx);
                _openLocation(f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(L.details),
              onTap: () {
                Navigator.pop(ctx);
                _showDetails(f);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text(L.delete, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteOne(f);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManager>();
    final active = manager.tasks.where((t) => t.isActive).toList();
    final finished = manager.tasks.where((t) => !t.isActive).toList();
    final files = _filtered;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting ? _selectionBar(files) : _normalBar(finished.isEmpty),
        body: RefreshIndicator(
          onRefresh: _refreshSaved,
          child: _body(context, active, files),
        ),
      ),
    );
  }

  PreferredSizeWidget _normalBar(bool noQueue) {
    return AppBar(
      title: Text(L.downloads),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: L.search,
          onPressed: () => setState(() => _searching = true),
        ),
        PopupMenuButton<_Sort>(
          icon: const Icon(Icons.sort),
          tooltip: L.sortBy,
          onSelected: (s) => setState(() => _sort = s),
          itemBuilder: (_) => [
            _sortItem(_Sort.newest, L.sortNewest, Icons.schedule),
            _sortItem(_Sort.largest, L.sortLargest, Icons.save),
            _sortItem(_Sort.name, L.sortName, Icons.sort_by_alpha),
          ],
        ),
        if (!_searching && !_selecting)
          IconButton(icon: const Icon(Icons.refresh), tooltip: L.refresh, onPressed: _refreshSaved),
        if (noQueue)
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: L.clearAll,
            onPressed: () => context.read<DownloadManager>().clearFinished(),
          ),
      ],
    );
  }

  PopupMenuItem<_Sort> _sortItem(_Sort s, String label, IconData icon) {
    final checked = _sort == s;
    return PopupMenuItem<_Sort>(
      value: s,
      child: Row(
        children: [
          Icon(icon, size: 18, color: checked ? Theme.of(context).colorScheme.primary : null),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          if (checked) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }

  PreferredSizeWidget _selectionBar(List<SavedFile> files) {
    final theme = Theme.of(context);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: L.exitSelection,
        onPressed: () => setState(_selected.clear),
      ),
      title: Text(L.selectedCount(_selected.length), style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: theme.colorScheme.primaryContainer,
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: L.selectAll,
          onPressed: () => setState(() {
            if (_selected.length == files.length) {
              _selected.clear();
            } else {
              _selected
                ..clear()
                ..addAll(files.map((f) => f.path));
            }
          }),
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: L.share,
          onPressed: () => _share(files.where((f) => _selected.contains(f.path)).toList()),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: L.delete,
          onPressed: () => _deleteBatch(files.where((f) => _selected.contains(f.path)).toList()),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, List<DownloadTask> active, List<SavedFile> files) {
    final theme = Theme.of(context);
    final empty = active.isEmpty && files.isEmpty && !_loadingSaved;

    if (empty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _query.isNotEmpty ? Icons.search_off : Icons.download_done_rounded,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(_query.isNotEmpty ? L.noResults : L.noDownloads, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (_saved.isNotEmpty || _loadingSaved) _summaryCard(theme),
        if (_searching)
          _searchField(theme)
        else if (_saved.isNotEmpty)
          _filterRow(theme),
        if (active.isNotEmpty) ...[
          _sectionHeader(context, '${L.activeDownloads} (${active.length})'),
          ...active.map((t) => DownloadTile(task: t)),
        ],
        if (!_loadingSaved && files.isNotEmpty) ...[
          _sectionHeader(context, '${L.savedFiles} (${files.length})'),
          ...files.map((f) => _SavedTile(
                file: f,
                selected: _selected.contains(f.path),
                selectionMode: _selecting,
                onOpen: () => _selecting ? _toggleSelect(f) : _open(f),
                onLongPress: () => _selecting ? _toggleSelect(f) : _toggleSelect(f),
                onMenu: () => _showFileMenu(f),
              )),
        ],
        if (_loadingSaved)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }

  /// Gradient storage summary — SnapTube-style header.
  Widget _summaryCard(ThemeData theme) {
    final total = _saved.fold<int>(0, (s, f) => s + f.sizeBytes);
    final videos = _saved.where((f) => f.isVideo).length;
    final audios = _saved.length - videos;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.folder_special_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_saved.length} ${L.savedFiles}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatBytes(total)} • ${L.storageUsed}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          _countChip('$videos', Icons.movie_rounded),
          const SizedBox(width: 6),
          _countChip('$audios', Icons.music_note_rounded),
        ],
      ),
    );
  }

  Widget _countChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 3),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _filterRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_Tab>(
              segments: [
                ButtonSegment(value: _Tab.all, label: Text(L.tabAll), icon: const Icon(Icons.grid_view_rounded, size: 16)),
                ButtonSegment(value: _Tab.video, label: Text(L.tabVideos), icon: const Icon(Icons.movie_rounded, size: 16)),
                ButtonSegment(value: _Tab.audio, label: Text(L.tabMusic), icon: const Icon(Icons.music_note_rounded, size: 16)),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: L.searchDownloads,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _searching = false;
              _query = '';
            }),
          ),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          filled: true,
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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

class _SavedTile extends StatelessWidget {
  const _SavedTile({
    required this.file,
    required this.selected,
    required this.selectionMode,
    required this.onOpen,
    required this.onLongPress,
    required this.onMenu,
  });

  final SavedFile file;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onMenu;

  /// Quality label embedded by the download engine: "Title [1080p60].mp4".
  String? get _quality {
    final m = RegExp(r'\[([^\]]+)\]').firstMatch(file.name);
    return m?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAudio = !file.isVideo;
    final ext = file.name.contains('.') ? file.name.split('.').last.toUpperCase() : '?';
    // Strip "[quality]" + extension for a cleaner title, like SnapTube.
    final title = file.name
        .replaceFirst(RegExp(r'\.[a-zA-Z0-9]+$'), '')
        .replaceFirst(RegExp(r'\s*\[[^\]]+\]$'), '');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        onTap: onOpen,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 74,
                height: 48,
                child: file.thumbUrl != null
                    ? Image.network(
                        file.thumbUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _iconBox(theme, isAudio),
                      )
                    : _iconBox(theme, isAudio),
              ),
            ),
            if (selectionMode)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? theme.colorScheme.primary.withValues(alpha: 0.45) : Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 26)
                      : const Icon(Icons.radio_button_unchecked, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_quality != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isAudio ? theme.colorScheme.tertiaryContainer : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        _quality!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isAudio ? theme.colorScheme.tertiary : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      '$ext • ${file.sizeBytes > 0 ? formatBytes(file.sizeBytes) : '—'} • '
                      '${file.modifiedAt.year}/${file.modifiedAt.month}/${file.modifiedAt.day}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // Where the file lives — shown right on the card.
              if (file.folderLabel.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 12, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        file.folderLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        trailing: selectionMode
            ? null
            : IconButton(icon: const Icon(Icons.more_vert), onPressed: onMenu),
      ),
    );
  }

  Widget _iconBox(ThemeData theme, bool isAudio) {
    return Container(
      width: 74,
      height: 48,
      color: isAudio ? theme.colorScheme.tertiaryContainer : theme.colorScheme.primaryContainer,
      child: Icon(
        isAudio ? Icons.music_note_rounded : Icons.movie_rounded,
        color: isAudio ? theme.colorScheme.tertiary : theme.colorScheme.primary,
      ),
    );
  }
}
