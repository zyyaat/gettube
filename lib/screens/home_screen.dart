import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/i18n.dart';
import '../services/youtube_service.dart';
import '../widgets/video_card.dart';
import 'video_screen.dart';

/// Home = YouTube search (plus direct URL paste) — the fastest path to a
/// download, same philosophy as SnapTube but without ads or redirects.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  VideoSearchList? _page;
  List<Video> _results = [];
  List<String> _recent = [];

  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _recent = prefs.getStringList('recent_searches') ?? []);
  }

  Future<void> _rememberQuery(String q) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList('recent_searches') ?? [])..remove(q);
    list.insert(0, q);
    if (list.length > 8) list.removeLast();
    await prefs.setStringList('recent_searches', list);
    _recent = list;
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;

    // Direct URL/id paste → open the video screen immediately.
    final id = YoutubeService.extractVideoId(q);
    if (id != null && (q.contains('youtu') || RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id))) {
      _focus.unfocus();
      try {
        final video = await YoutubeService.getVideo(id);
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(video: video)));
        return;
      } catch (_) {
        // fall through to normal search
      }
    }

    _focus.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _page = null;
    });
    try {
      final page = await YoutubeService.search(q);
      await _rememberQuery(q);
      if (!mounted) return;
      setState(() {
        _page = page;
        _results = page.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final page = _page;
    if (page == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await page.nextPage();
      if (!mounted) return;
      setState(() {
        if (more != null && more.isNotEmpty) {
          _results.addAll(more);
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_for_offline_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            const Text('GetTube', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ],
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _runSearch,
              decoration: InputDecoration(
                hintText: L.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                filled: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Recent searches
          if (_results.isEmpty && !_loading && _recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(L.recentSearches, style: theme.textTheme.labelLarge),
                      const Spacer(),
                      TextButton(onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('recent_searches');
                        setState(() => _recent = []);
                      }, child: Text(L.clearAll)),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 0,
                    children: _recent
                        .map((q) => ActionChip(
                              label: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onPressed: () {
                                _controller.text = q;
                                _runSearch(q);
                              },
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          // Body
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(L.error, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall, maxLines: 3),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => _runSearch(_controller.text),
                child: Text(L.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return _emptyState(context);
    }
    return ListView.builder(
      itemCount: _results.length + 1,
      itemBuilder: (context, i) {
        if (i == _results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton.tonal(
                      onPressed: _loadMore,
                      child: Text(L.loadMore),
                    ),
            ),
          );
        }
        final v = _results[i];
        return VideoCard(
          video: v,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(video: v))),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.download_rounded, size: 52, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(L.heroTagline, textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _chip(context, Icons.hd, L.featAllQualities),
                _chip(context, Icons.block, L.featNoAds),
                _chip(context, Icons.lock_open, L.featNoPaywall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}
