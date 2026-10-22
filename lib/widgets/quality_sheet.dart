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
///
/// Two-step CONFIRM flow (user requested):
///  1. Tapping a row only SELECTS it (its color lights up) — nothing starts.
///  2. The download button at the bottom stays dimmed/disabled until a
///     quality is selected; then it lights up and starts the download.
class QualitySheet extends StatefulWidget {
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

  @override
  State<QualitySheet> createState() => _QualitySheetState();
}

class _QualitySheetState extends State<QualitySheet> {
  QualityOption? _selected;

  List<QualityOption> _of(QualityKind k) => widget.options.where((o) => o.kind == k).toList();

  void _start(QualityOption option) {
    final messenger = ScaffoldMessenger.of(context);
    DownloadManager.instance.enqueue(
      videoId: widget.video.id.value,
      title: widget.video.title,
      thumbnailUrl: widget.video.thumbnails.mediumResUrl,
      channel: widget.video.author,
      option: option,
      duration: widget.video.duration,
    );
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${L.downloadStarted} — ${option.label}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muxed = _of(QualityKind.muxed);
    final videoOnly = _of(QualityKind.videoOnly);
    final audioOnly = _of(QualityKind.audioOnly);
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    final sel = _selected;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Text(widget.video.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.options.length} ${L.chooseQuality} • ${L.free} ✦ ${L.featNoAds}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (videoOnly.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Expanded(child: Text(L.autoMuxNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),

                    // High-quality section first — this is the differentiator.
                    if (videoOnly.isNotEmpty) _sectionTitle(context, L.sectionHigh, Icons.high_quality),
                    ...videoOnly.map((o) => _OptionTile(
                          option: o,
                          selected: sel == o,
                          onSelect: () => setState(() => _selected = o),
                        )),

                    if (muxed.isNotEmpty) _sectionTitle(context, L.sectionReady, Icons.flash_on),
                    ...muxed.map((o) => _OptionTile(
                          option: o,
                          selected: sel == o,
                          onSelect: () => setState(() => _selected = o),
                        )),

                    if (audioOnly.isNotEmpty) _sectionTitle(context, L.sectionAudio, Icons.music_note),
                    ...audioOnly.map((o) => _OptionTile(
                          option: o,
                          selected: sel == o,
                          onSelect: () => setState(() => _selected = o),
                        )),

                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            // Confirm bar — dimmed until a quality is selected.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: sel == null ? null : () => _start(sel),
                  icon: const Icon(Icons.download_rounded, size: 22),
                  label: Text(
                    sel == null ? L.download : '${L.download} — ${sel.label}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
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
  const _OptionTile({required this.option, required this.selected, required this.onSelect});

  final QualityOption option;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAudio = option.kind == QualityKind.audioOnly;
    // Selected rows light up with the primary color; the "recommended" badge
    // keeps its highlight when the row is not selected.
    final color = (selected || option.recommended) ? theme.colorScheme.primary : null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: selected ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onSelect,
        leading: CircleAvatar(
          backgroundColor: selected
              ? theme.colorScheme.primary
              : (color ?? theme.colorScheme.primaryContainer).withValues(alpha: 0.15),
          child: Icon(
            isAudio ? Icons.audiotrack : Icons.videocam,
            color: selected ? theme.colorScheme.onPrimary : (color ?? theme.colorScheme.primary),
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
          '${option.container} • ${formatBytes(option.sizeBytes)}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
            : Icon(Icons.radio_button_unchecked, color: theme.colorScheme.outline),
      ),
    );
  }
}
