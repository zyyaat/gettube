import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/i18n.dart';
import '../models/download_task.dart';
import '../services/download_manager.dart';
import '../state/settings_controller.dart';

/// A row for an active/finished/failed download task with live progress.
class DownloadTile extends StatelessWidget {
  const DownloadTile({super.key, required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    task.thumbnailUrl,
                    width: 64,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 64,
                      height: 40,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.videocam, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              task.option.label,
                              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _statusText(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _statusColor(theme),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ..._actions(context),
              ],
            ),
            if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.paused) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${formatBytes(task.received)} / ${formatBytes(task.total)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (task.status == DownloadStatus.downloading)
                    Text(
                      formatSpeed(task.speedBps),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ] else if (task.status == DownloadStatus.processing || task.status == DownloadStatus.saving) ...[
              // Merging/converting and the final copy used to look frozen —
              // always show a live bar in these phases.
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: task.status == DownloadStatus.processing && task.processProgress > 0
                      ? task.processProgress
                      : null,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                task.status == DownloadStatus.saving
                    ? L.saving
                    : task.processProgress > 0
                        ? '${(task.processProgress * 100).round()}%'
                        : L.processing,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (task.status == DownloadStatus.waitingForWifi) ...[
              const SizedBox(height: 8),
              Text(
                L.wifiGateHint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await context.read<SettingsController>().setMobileDataAllowed(true);
                  DownloadManager.instance.refresh();
                },
                icon: const Icon(Icons.network_cell_rounded, size: 18),
                label: Text(L.allowMobileData),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
            if (task.status == DownloadStatus.failed && task.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  task.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusText() {
    switch (task.status) {
      case DownloadStatus.queued:
        return L.queued;
      case DownloadStatus.fetching:
        return L.preparing;
      case DownloadStatus.downloading:
        return L.downloading;
      case DownloadStatus.processing:
        return task.processProgress > 0
            ? '${L.processing} ${(task.processProgress * 100).round()}%'
            : L.processing;
      case DownloadStatus.saving:
        return L.saving;
      case DownloadStatus.waitingForWifi:
        return L.waitingForWifi;
      case DownloadStatus.paused:
        return L.paused;
      case DownloadStatus.completed:
        return L.completed;
      case DownloadStatus.failed:
        return L.failed;
      case DownloadStatus.canceled:
        return L.canceled;
    }
  }

  Color _statusColor(ThemeData theme) {
    switch (task.status) {
      case DownloadStatus.completed:
        return theme.colorScheme.primary;
      case DownloadStatus.failed:
      case DownloadStatus.canceled:
        return theme.colorScheme.error;
      case DownloadStatus.paused:
      case DownloadStatus.waitingForWifi:
        return theme.colorScheme.tertiary;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  List<Widget> _actions(BuildContext context) {
    switch (task.status) {
      case DownloadStatus.queued:
      case DownloadStatus.fetching:
      case DownloadStatus.downloading:
      case DownloadStatus.processing:
      case DownloadStatus.saving:
        return [
          IconButton(
            tooltip: L.pause,
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: () => DownloadManager.instance.pause(task),
          ),
          IconButton(
            tooltip: L.cancel,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => DownloadManager.instance.cancel(task),
          ),
        ];
      case DownloadStatus.paused:
        return [
          IconButton(
            tooltip: L.resume,
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => DownloadManager.instance.resume(task),
          ),
          IconButton(
            tooltip: L.cancel,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => DownloadManager.instance.cancel(task),
          ),
        ];
      case DownloadStatus.waitingForWifi:
        return [
          IconButton(
            tooltip: L.pause,
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: () => DownloadManager.instance.pause(task),
          ),
          IconButton(
            tooltip: L.cancel,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => DownloadManager.instance.cancel(task),
          ),
        ];
      case DownloadStatus.failed:
      case DownloadStatus.canceled:
        return [
          IconButton(
            tooltip: L.retry,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => DownloadManager.instance.retry(task),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => DownloadManager.instance.remove(task),
          ),
        ];
      case DownloadStatus.completed:
        return [
          const Icon(Icons.check_circle, color: Color(0xFF00C853)),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => DownloadManager.instance.remove(task),
          ),
        ];
    }
  }
}
