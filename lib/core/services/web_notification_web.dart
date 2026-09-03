import 'dart:js_interop';

/// Static-interop binding for the plain-JS bridge set up in web/index.html
/// (there's no Dart-native way to call the browser's Notification API
/// directly). Resolves against the global JS scope, i.e.
/// `window.hyportShowNotification(title, body, ticketId)`.
@JS('hyportShowNotification')
external void _showNotificationJS(JSString title, JSString body, JSString ticketId);

void showWebNotification({required String title, required String body, String? ticketId}) {
  _showNotificationJS(title.toJS, body.toJS, (ticketId ?? '').toJS);
}
