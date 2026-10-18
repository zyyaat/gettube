import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/formatters.dart';
import '../core/i18n.dart';
import '../services/youtube_service.dart';
import '../widgets/quality_sheet.dart';

/// Video details + entry points to the all-qualities download sheet.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.video});

  final Video video;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  bool _openingVideo = false;
  bool _openingAudio = false;

  Future<void> _openSheet({required bool audioOnly}) async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() {
      if (audioOnly) {
        _openingAudio = true;
      } else {
        _openingVideo = true;
      }
    });
    try {
      final options = await YoutubeService.getQualityOptions(widget.video);
      final filtered = audioOnly
          ? options.where((o) => o.kind == QualityKind.audioOnly).toList()
          : options.where((o) => o.kind != QualityKind.audioOnly).toList();
      if (!mounted) return;
      if (filtered.isEmpty) {
        scaffold.showSnackBar(SnackBar(content: Text(L.qualityNotAvailable)));
        return;
      }
      await QualitySheet.show(context, video: widget.video, options: filtered);
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('${L.qualitiesFailed}\n$e')));
    } finally {
      if (mounted) {
        setState(() {
          _openingAudio = false;
          _openingVideo = false;
        });
      }
    }
  }

  Future<void> _openInYouTube() async {
    final uri = Uri.parse('https://www.youtube.com/watch?v=${widget.video.id.value}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = widget.video;

    return Scaffold(
      appBar: AppBar(title: const Text('GetTube')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                v.thumbnails.maxResUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.network(
                  v.thumbnails.highResUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.movie_outlined, size: 48),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(v.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(child: Text(v.author, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 12),
              if (v.viewCount != null) ...[
                Icon(Icons.visibility_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${formatCount(v.viewCount!)} ${L.views}', style: theme.textTheme.bodyMedium),
              ],
              if (v.duration != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(formatDuration(v.duration), style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
          const SizedBox(height: 24),

          // Download buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _openingVideo ? null : () => _openSheet(audioOnly: false),
                  icon: _openingVideo
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.videocam_rounded),
                  label: Text(L.downloadVideo),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _openingAudio ? null : () => _openSheet(audioOnly: true),
                  icon: _openingAudio
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.audiotrack_rounded),
                  label: Text(L.downloadAudio),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: _openInYouTube,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(L.openInYouTube),
            ),
          ),
        ],
      ),
    );
  }
}
