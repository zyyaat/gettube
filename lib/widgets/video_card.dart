import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/formatters.dart';
import '../core/i18n.dart';
import '../services/youtube_service.dart';
import 'quality_sheet.dart';

/// Search-result card. Two actions:
///  • tap anywhere  -> open the video screen (full quality sheet)
///  • download icon -> jump STRAIGHT to the quality sheet, no video page
///    (SnapTube-style "download from the list" shortcut).
class VideoCard extends StatefulWidget {
  const VideoCard({super.key, required this.video, required this.onTap});

  final Video video;
  final VoidCallback onTap;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _busy = false;

  /// Fetches the quality options and opens the quality sheet directly,
  /// skipping the video screen entirely.
  Future<void> _quickDownload() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final options = await YoutubeService.getQualityOptions(widget.video);
      if (!mounted) return;
      await QualitySheet.show(context, video: widget.video, options: options);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.error), duration: const Duration(seconds: 2)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail with duration badge
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      widget.video.thumbnails.mediumResUrl,
                      width: 148,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 148,
                        height: 84,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.play_circle_outline, size: 32),
                      ),
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          width: 148,
                          height: 84,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned.directional(
                    textDirection: Directionality.of(context),
                    end: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatDuration(widget.video.duration),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Texts
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.video.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.video.engagement.viewCount > 0 ? formatCount(widget.video.engagement.viewCount) : ''} ${L.views}'
                      '${widget.video.uploadDate != null ? ' • ${widget.video.uploadDate!.year}/${widget.video.uploadDate!.month}/${widget.video.uploadDate!.day}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Quick-download button — opens the quality sheet from the list.
              const SizedBox(width: 6),
              _QuickDownloadButton(busy: _busy, onTap: _quickDownload),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickDownloadButton extends StatelessWidget {
  const _QuickDownloadButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: busy
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
              )
            : Icon(
                Icons.download_rounded,
                size: 22,
                color: theme.colorScheme.primary,
              ),
      ),
    );
  }
}
