/// Shows a real browser Notification for a foreground FCM message — real
/// implementation on web (web_notification_web.dart, backed by the JS
/// bridge in web/index.html), a no-op stub everywhere else
/// (web_notification_stub.dart, since flutter_local_notifications covers
/// Android/iOS instead — see LocalNotificationService).
library;

export 'web_notification_stub.dart' if (dart.library.js_interop) 'web_notification_web.dart';
