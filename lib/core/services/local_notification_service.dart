import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hyport/core/services/web_notification.dart';

/// Shows a real OS notification-bar/tray pop-up (with sound) for a
/// foreground FCM message — Firebase's SDKs only auto-display a system
/// notification for background/terminated app state; a message that
/// arrives while the app is open and focused has to be surfaced manually,
/// otherwise it's silent (previously: just an in-app SnackBar, easy to
/// miss and impossible to hear).
///
/// flutter_local_notifications has no web implementation, so web routes
/// through a small JS bridge (web_notification.dart) using the browser's
/// own Notification API instead — same OS-level pop-up, different
/// mechanism, since the two can't share a plugin.
class LocalNotificationService {
  LocalNotificationService._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Set by PushNotificationListener — routes a tap on a foreground-shown
  /// local notification to its ticket (FCM's own onMessageOpenedApp doesn't
  /// fire for notifications we render ourselves).
  static void Function(String ticketId)? onTicketTap;

  static const _androidChannel = AndroidNotificationChannel(
    'hyport_default',
    'Ticket & chat notifications',
    description: 'Ticket updates and chat messages',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static void _handleResponse(NotificationResponse response) {
    final ticketId = response.payload;
    if (ticketId != null && ticketId.isNotEmpty) onTicketTap?.call(ticketId);
  }

  static Future<void> init() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Alert/sound/badge permission is already requested by
    // PushNotificationService.requestPermission() (shared UNUserNotification
    // Center API on iOS) — asking again here would just double-prompt.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _handleResponse,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  /// [badgeCount] — the recipient's unread total, shown on the app-icon
  /// badge (iOS natively; some Android launchers use the notification's
  /// `number`). [ticketId] routes a tap.
  static Future<void> show({
    required String title,
    required String body,
    String? ticketId,
    int? badgeCount,
  }) async {
    if (kIsWeb) {
      showWebNotification(title: title, body: body, ticketId: ticketId);
      return;
    }
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          number: badgeCount,
        ),
        iOS: DarwinNotificationDetails(
          presentSound: true,
          presentAlert: true,
          presentBadge: true,
          badgeNumber: badgeCount,
        ),
      ),
      payload: ticketId,
    );
  }
}
