import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/i18n.dart';
import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/crash_log.dart';
import 'services/download_manager.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  // Capture EVERY error into CrashLog — release builds used to fail silently
  // (a blank white screen) when anything threw before the first frame.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashLog.write('FLUTTER: ${details.exceptionAsString()}', details.stack);
    };

    PlatformDispatcher.instance.onError = (e, st) {
      CrashLog.write('PLATFORM: $e', st);
      return true;
    };

    // In release builds the default error widget is an empty gray box.
    // Render a readable message instead so failures are never invisible.
    ErrorWidget.builder = (details) {
      CrashLog.write('WIDGET: ${details.exceptionAsString()}', details.stack);
      return _ErrorBox(message: details.exceptionAsString());
    };

    // IMPORTANT: runApp() is called with ZERO awaits before it. All heavy
    // initialization happens after the first frame inside BootstrapApp, so
    // even a total init failure shows a visible error screen — never a
    // silent white screen.
    runApp(const BootstrapApp());
  }, (e, st) {
    CrashLog.write('ZONE: $e', st);
  });
}

/// Boots the app safely: splash first frame → guarded init → real app,
/// with a full error screen (retry / copy) if initialization ever fails.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  SettingsController? _settings;
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    try {
      final s = SettingsController();
      await s.load();
      // s.load() already applies every setting (incl. save location and
      // mobile-data gate) to the download engine — nothing extra to copy.

      await StorageService.clearTemps();
      unawaited(NotificationService.init());

      if (mounted) {
        setState(() {
          _settings = s;
          _error = null;
          _stack = null;
        });
      }
    } catch (e, st) {
      CrashLog.write('BOOT FAILED: $e', st);
      if (mounted) {
        setState(() {
          _error = e;
          _stack = st;
        });
      }
    }
  }

  ThemeData _bootTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.seed,
          brightness: Brightness.dark,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _bootTheme(),
        home: _BootErrorScreen(error: _error!, stack: _stack, onRetry: _boot),
      );
    }
    if (_settings == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _bootTheme(),
        home: const _SplashScreen(),
      );
    }
    return GetTubeApp(settings: _settings!);
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.download_rounded, size: 52, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text('GetTube',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.error, required this.stack, required this.onRetry});

  final Object error;
  final StackTrace? stack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = error.toString();
    final st = stack?.toString() ?? '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                L.lang == AppLang.arabic ? 'تعذر تشغيل GetTube' : 'GetTube failed to start',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                L.lang == AppLang.arabic
                    ? 'اضغط "إعادة المحاولة"، أو انسخ التفاصيل وأرسلها لنا لإصلاح المشكلة سريعاً.'
                    : 'Tap "Try again", or copy the details and send them to us so we can fix it fast.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      st.isEmpty ? text : '$text\n\n$st',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: Text(L.lang == AppLang.arabic ? 'إعادة المحاولة' : 'Try again'),
                onPressed: onRetry,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: Text(L.lang == AppLang.arabic ? 'نسخ التفاصيل' : 'Copy details'),
                onPressed: () async {
                  final full = st.isEmpty ? text : '$text\n\n$st';
                  try {
                    await Clipboard.setData(ClipboardData(text: full));
                  } catch (_) {}
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Readable error surface used instead of the invisible gray box in release.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFB3261E),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bug_report_rounded, color: Colors.white, size: 40),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 12,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class GetTubeApp extends StatelessWidget {
  const GetTubeApp({super.key, required this.settings});

  final SettingsController settings;

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.seed,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.comfortable,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: DownloadManager.instance),
      ],
      child: Consumer<SettingsController>(
        builder: (context, s, _) {
          L.lang = s.lang;
          return MaterialApp(
            title: 'GetTube',
            debugShowCheckedModeBanner: false,
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            themeMode: s.themeMode,
            locale: Locale(s.lang.code),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const RootShell(),
          );
        },
      ),
    );
  }
}

/// Bottom navigation shell: Home (search) / Downloads / Settings.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowDisclaimer());
  }

  Future<void> _maybeShowDisclaimer() async {
    final settings = context.read<SettingsController>();
    if (settings.seenDisclaimer) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(L.disclaimerTitle),
        content: Text(L.disclaimerBody),
        actions: [
          FilledButton(
            onPressed: () {
              settings.acknowledgeDisclaimer();
              Navigator.of(ctx).pop();
            },
            child: Text(L.letsGo),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const HomeScreen(), const DownloadsScreen(), const SettingsScreen()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.search_outlined),
            selectedIcon: const Icon(Icons.search),
            label: L.search,
          ),
          NavigationDestination(
            icon: const Icon(Icons.download_outlined),
            selectedIcon: const Icon(Icons.download),
            label: L.downloads,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: L.settings,
          ),
        ],
      ),
    );
  }
}
