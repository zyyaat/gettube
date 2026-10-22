import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Minimal, fully-guarded completion notifications.
/// If anything fails the app keeps working silently.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _id = 100;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<void> ensurePermission() async {
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  static Future<void> showDone(String videoTitle, String fileName) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        _id++,
        'GetTube ✓',
        fileName,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gettube_downloads',
            'GetTube Downloads',
            channelDescription: 'Download completion notifications',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }
}
