import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'crash_log.dart';

/// The result of one browser-session capture: googlevideo URLs keyed by
/// their itag, plus the exact User-Agent of the session that minted them
/// (Google's video servers expect downloads to present a matching
/// fingerprint).
class CapturedSession {
  CapturedSession(this.urls, this.userAgent);
  final Map<int, Uri> urls;
  final String userAgent;
}

/// Resolves stream URLs by letting a REAL, invisible browser session play
/// the video once — right on the user's device.
///
/// WHY THIS EXISTS: YouTube's 2026 bot gate answers every innertube API
/// client with "Sign in to confirm you're not a bot" on flagged networks —
/// the block is IP-level and no API client can pass it. A genuine browser
/// is a different story: YouTube's own web player runs BotGuard, mints its
/// PO tokens and deciphers its signatures exactly like it does for every
/// human viewer. So we open the watch page in a hidden WebView, press play
/// (muted), sweep through the quality levels, and simply LISTEN to the
/// playback traffic — recording the fully-signed googlevideo URLs per itag
/// while the page plays normally.
///
/// This is the client-side equivalent of what commercial downloaders run
/// on their server farms — no login, no accounts, no backend. (SnapTube's
/// servers do the same job, paid with ads and — historically — with secret
/// unrelated file downloads; see Upstream Security 2019 / SMEX 2023.)
class BrowserSession {
  BrowserSession._();

  /// The app's navigator — the hidden player view is attached to this
  /// overlay (an attached view is what lets the page's player run at all).
  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  static final Map<String, CapturedSession> _cache = {};
  static Future<void> _chain = Future<void>.value();

  /// Serializes captures — one hidden browser at a time keeps RAM sane on
  /// low-end phones.
  static Future<CapturedSession> capture(
    String videoId, {
    Set<int>? wantedTags,
    Duration timeout = const Duration(seconds: 24),
  }) {
    final run = _chain.then(
        (_) => _captureNow(videoId, wantedTags: wantedTags, timeout: timeout));
    _chain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  static Future<CapturedSession> _captureNow(
    String videoId, {
    Set<int>? wantedTags,
    required Duration timeout,
  }) async {
    final cached = _cache[videoId];
    if (cached != null &&
        (wantedTags == null || wantedTags.every(cached.urls.containsKey))) {
      return cached;
    }

    final urls = <int, Uri>{};
    InAppWebViewController? controller;
    OverlayEntry? entry;
    var done = false;

    bool satisfied() {
      if (urls.isEmpty) return false;
      if (wantedTags == null) return urls.length >= 2;
      return wantedTags.every(urls.containsKey);
    }

    // Fire-and-forget JS runner — never let a missing page element throw.
    Future<void> kick(String js) async {
      try {
        await controller?.evaluateJavascript(source: js);
      } catch (_) {}
    }

    final webview = InAppWebView(
      initialUrlRequest: URLRequest(
          url: WebUri(
              'https://www.youtube.com/watch?v=$videoId&bpctr=9999999999&has_verified=1&hl=en')),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: true,
        supportZoom: false,
        disableContextMenu: true,
      ),
      onWebViewCreated: (c) => controller = c,
      shouldInterceptRequest: (c, request) async {
        final u = request.url;
        if (u.host.endsWith('googlevideo.com') &&
            u.path.contains('videoplayback')) {
          final itag = int.tryParse(u.queryParameters['itag'] ?? '');
          if (itag != null) urls[itag] = u;
        }
        return null; // observe only — the page keeps playing normally
      },
      onLoadStop: (c, url) async {
        // Auto-dismiss a consent interstitial when one shows up.
        await kick('''
(function(){
  var sels = ['button[aria-label*="Accept all"]','button[aria-label*="Accept"]','button[aria-label*="قبول"]','form[action*="consent"] button'];
  for (var i = 0; i < sels.length; i++) { var b = document.querySelector(sels[i]); if (b) { b.click(); return 'clicked'; } }
  return 'none';
})();
''');
        // Muted autoplay — YouTube's own player does every hard part.
        await kick('''
(function(){
  var v = document.querySelector('video');
  if (v) { v.muted = true; v.play().catch(function(){}); }
  var p = document.getElementById('movie_player');
  if (p) { try { p.mute(); } catch(e){} if (p.playVideo) p.playVideo(); }
  return 'played';
})();
''');
      },
    );

    // Quality sweep — provokes fresh adaptive requests (new itags) which
    // the interceptor above records. Sweeps top-down, then re-kicks play.
    const levels = ['hd2160', 'hd1440', 'hd1080', 'hd720', 'large', 'medium'];
    var step = -1;
    Timer? sweep;
    try {
      final overlay = navKey.currentState?.overlay;
      if (overlay == null) throw Exception('app overlay not ready yet');
      entry = OverlayEntry(
        builder: (_) => IgnorePointer(
          child: Positioned(
            right: 0,
            bottom: 0,
            width: 160,
            height: 120,
            child: Opacity(opacity: 0.02, child: webview),
          ),
        ),
      );
      overlay.insert(entry);
      sweep = Timer.periodic(const Duration(milliseconds: 2400), (_) {
        if (done) return;
        step++;
        final q = step < levels.length ? "'${levels[step]}'" : 'null';
        kick('''
(function(){
  try {
    var p = document.getElementById('movie_player');
    if (!p || !p.getAvailableQualityLevels) return 'noplayer';
    var lv = (p.getAvailableQualityLevels() || []).filter(function(x){ return x && x !== 'auto'; });
    if (!lv.length) return 'empty';
    var target = $q && lv.indexOf($q) >= 0 ? $q : null;
    if (target) { if (p.setPlaybackQualityRange) p.setPlaybackQualityRange(target, target); else if (p.setPlaybackQuality) p.setPlaybackQuality(target); }
    var v = document.querySelector('video');
    if (v && v.paused) { v.muted = true; v.play().catch(function(){}); }
    return 'ok';
  } catch (e) { return 'err'; }
})();
''');
      });

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (satisfied()) break;
      }
    } finally {
      done = true;
      sweep?.cancel();
      try {
        entry?.remove();
      } catch (_) {}
    }

    var ua = '';
    try {
      final r =
          await controller?.evaluateJavascript(source: 'navigator.userAgent');
      if (r != null && r.toString().isNotEmpty) {
        ua = r.toString().replaceAll('"', '').trim();
      }
    } catch (_) {}
    ua = ua.isEmpty ? _fallbackUa : ua;

    final session = CapturedSession(Map.of(urls), ua);
    if (session.urls.isNotEmpty) {
      _cache[videoId] = session;
      CrashLog.write(
          'BROWSER session: captured itags ${session.urls.keys.toList()} for $videoId');
    } else {
      CrashLog.write('BROWSER session: nothing captured for $videoId (page never played?)');
    }
    return session;
  }

  static const _fallbackUa =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
}
