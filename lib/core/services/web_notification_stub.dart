/// Non-web platforms — flutter_local_notifications handles this instead
/// (see LocalNotificationService), so this is always a no-op. See
/// web_notification.dart for the conditional export that picks this vs.
/// the real web implementation.
void showWebNotification({required String title, required String body, String? ticketId}) {}
