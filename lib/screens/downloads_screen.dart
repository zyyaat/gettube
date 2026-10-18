import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/i18n.dart';
import '../models/saved_file.dart';
import '../services/download_manager.dart';
import '../services/storage_service.dart';
import '../widgets/download_tile.dart';

/// Live queue + persisted library of saved files.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<SavedFile> _saved = [];
  bool _loadingSaved = true;

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
    });
  }

  Future<void> _open(SavedFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    if (f.path.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(L.fileMissing)));
      return;
    }
    final res = await OpenFilex.open(f.path);
    if (res.type != ResultType.done) {
      messenger.showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  Future<void> _delete(SavedFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    await StorageService.deleteSaved(f);
    await _refreshSaved();
    messenger.showSnackBar(SnackBar(content: Text(L.fileDeleted)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = context.watch<DownloadManager>();
    final active = manager.tasks.where((t) => t.isActive).toList();
    final finished = manager.tasks.where((t) => !t.isActive).toList();
    final rows = [...active, ...finished];

    return Scaffold(
      appBar: AppBar(
        title: Text(L.downloads),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshSaved, tooltip: L.refresh),
          if (rows.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: L.clearAll,
              onPressed: () => manager.clearFinished(),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSaved,
        child: rows.isEmpty && _saved.isEmpty
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download_done_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(L.noDownloads, style: theme.textTheme.titleMedium),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                children: [
                  if (rows.isNotEmpty) ...[
                    _header(context, '${L.activeDownloads} (${active.length})'),
                    ...rows.map((t) => DownloadTile(task: t)),
                  ],
                  if (_saved.isNotEmpty) ...[
                    _header(context, '${L.savedFiles} (${_saved.length})'),
                    if (_loadingSaved)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      ..._saved.map((f) => _SavedTile(file: f, onOpen: () => _open(f), onDelete: () => _delete(f))),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) {
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
  const _SavedTile({required this.file, required this.onOpen, required this.onDelete});

  final SavedFile file;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = file.name.contains('.') ? file.name.split('.').last.toUpperCase() : '?';
    final isAudio = !file.isVideo;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onOpen,
        leading: CircleAvatar(
          backgroundColor: isAudio ? theme.colorScheme.tertiaryContainer : theme.colorScheme.primaryContainer,
          child: Icon(
            isAudio ? Icons.music_note_rounded : Icons.movie_rounded,
            color: isAudio ? theme.colorScheme.tertiary : theme.colorScheme.primary,
          ),
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$ext • ${file.sizeBytes > 0 ? formatBytes(file.sizeBytes) : '—'} • ${file.modifiedAt.year}/${file.modifiedAt.month}/${file.modifiedAt.day}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmDelete(context),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.delete),
        content: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: Text(L.delete),
          ),
        ],
      ),
    );
  }
}
