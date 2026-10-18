import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/formatters.dart';
import '../core/i18n.dart';
import '../models/quality_option.dart';
import '../services/download_manager.dart';

/// Bottom sheet listing EVERY quality YouTube offers for the video:
///  • muxed (instant) rows
///  • high-quality video-only rows (auto-muxed with best audio)
///  • audio-only rows (native M4A/Opus + MP3 conversion)
/// All free — no "premium" locks, ever.
class QualitySheet extends StatelessWidget {
  const QualitySheet({super.key, required this.video, required this.options});

  final Video video;
  final List<QualityOption> options;

  static Future<void> show(BuildContext context, {required Video video, required List<QualityOption> options}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QualitySheet(video: video, options: options),
    );
  }

  List<QualityOption> _of(QualityKind k) => options.where((o) => o.kind == k).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muxed = _of(QualityKind.muxed);
    final videoOnly = _of(QualityKind.videoOnly);
    final audioOnly = _of(QualityKind.audioOnly);
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Text(video.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${options.length} ${L.chooseQuality} • ${L.free} ✦ ${L.featNoAds}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (videoOnly.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.merge, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(child: Text(L.autoMuxNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                  ],
                ),
              ],
              const SizedBox(height: 10),

              // High-quality section first — this is the differentiator.
              if (videoOnly.isNotEmpty) _sectionTitle(context, L.sectionHigh, Icons.high_quality),
              ...videoOnly.map((o) => _OptionTile(option: o, video: video)),

              if (muxed.isNotEmpty) _sectionTitle(context, L.sectionReady, Icons.flash_on),
              ...muxed.map((o) => _OptionTile(option: o, video: video)),

              if (audioOnly.isNotEmpty) _sectionTitle(context, L.sectionAudio, Icons.music_note),
              ...audioOnly.map((o) => _OptionTile(option: o, video: video)),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.video});

  final QualityOption option;
  final Video video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAudio = option.kind == QualityKind.audioOnly;
    final color = option.recommended ? theme.colorScheme.primary : null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        onTap: () => _start(context),
        leading: CircleAvatar(
          backgroundColor: (color ?? theme.colorScheme.primaryContainer).withValues(alpha: 0.15),
          child: Icon(
            isAudio ? Icons.audiotrack : Icons.videocam,
            color: color ?? theme.colorScheme.primary,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              option.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (option.recommended) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  L.recommended,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimary, fontSize: 10),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${option.container} • ${formatBytes(option.sizeBytes)}'
          '${option.kind == QualityKind.videoOnly ? ' • ${L.processing.split("…").first}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Icon(Icons.download_rounded, color: theme.colorScheme.primary),
      ),
    );
  }

  void _start(BuildContext context) {
    DownloadManager.instance.enqueue(
      videoId: video.id.value,
      title: video.title,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      channel: video.author,
      option: option,
      duration: video.duration,
    );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${L.downloadStarted} — ${option.label}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
