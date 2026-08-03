import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/notifications/data/notification_repository.dart';
import 'package:hyport/features/notifications/domain/app_notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(firestoreProvider));
});

final userNotificationsProvider =
    StreamProvider.autoDispose.family<List<AppNotification>, String>((ref, userId) {
  return ref.watch(notificationRepositoryProvider).watchForUser(userId);
});

final unreadNotificationCountProvider = Provider.autoDispose.family<int, String>((ref, userId) {
  final notifications = ref.watch(userNotificationsProvider(userId)).valueOrNull ?? [];
  return notifications.where((n) => !n.read).length;
});
