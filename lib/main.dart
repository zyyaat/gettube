import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/i18n.dart';
import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/download_manager.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsController();
  await settings.load();

  DownloadManager.instance
    ..maxConcurrent = settings.maxConcurrent
    ..savePublic = settings.savePublic;

  await StorageService.clearTemps();
  unawaited(NotificationService.init());

  runApp(GetTubeApp(settings: settings));
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
