import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Web push (unlike Android/iOS) needs a VAPID key from Firebase Console ->
/// Project settings -> Cloud Messaging -> Web Push certificates. Left blank
/// until that's generated; requestToken() below no-ops on web until it's
/// filled in rather than throwing, so the rest of the app (mobile push,
/// in-app notification list) works either way. See DECISIONS.md.
const String webPushVapidKey = '';

/// Thin wrapper over FirebaseMessaging: permission request + token
/// retrieval. Token persistence (saving it to the signed-in user's
/// Firestore doc) and foreground/tap handling live in
/// PushNotificationListener, which is the thing actually wired into the
/// widget tree — this class just talks to the platform.
class PushNotificationService {
  final FirebaseMessaging _messaging;

  PushNotificationService(this._messaging);

  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Returns null if permission was denied, or (on web) if no VAPID key is
  /// configured yet — both are expected states this app must degrade
  /// gracefully through, not crash on.
  Future<String?> getToken() async {
    if (kIsWeb && webPushVapidKey.isEmpty) return null;
    try {
      return await _messaging.getToken(vapidKey: kIsWeb ? webPushVapidKey : null);
    } catch (_) {
      return null;
    }
  }

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  Stream<RemoteMessage> get onForegroundMessage => FirebaseMessaging.onMessage;

  Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp;

  Future<RemoteMessage?> get initialMessage => _messaging.getInitialMessage();
}
