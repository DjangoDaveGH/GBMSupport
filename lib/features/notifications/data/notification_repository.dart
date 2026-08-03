import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/features/notifications/domain/app_notification.dart';

class NotificationRepository {
  final FirebaseFirestore _db;

  NotificationRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _notifications => _db.collection('notifications');

  Stream<List<AppNotification>> watchForUser(String userId, {int limit = 50}) {
    return _notifications
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AppNotification.fromMap(d.id, d.data())).toList());
  }

  Future<void> markRead(String notificationId) {
    return _notifications.doc(notificationId).update({'read': true});
  }

  Future<void> markAllRead(List<String> notificationIds) async {
    final batch = _db.batch();
    for (final id in notificationIds) {
      batch.update(_notifications.doc(id), {'read': true});
    }
    await batch.commit();
  }

  /// Admin-triggered broadcast (system downtime / deadline / maintenance
  /// notices) — see Section 7: full scheduling is out of scope for the MVP.
  Future<void> broadcast({
    required List<String> userIds,
    required String type,
    required String message,
  }) async {
    final batch = _db.batch();
    final now = Timestamp.now();
    for (final userId in userIds) {
      final ref = _notifications.doc();
      batch.set(ref, {
        'userId': userId,
        'ticketId': null,
        'type': type,
        'message': message,
        'read': false,
        'createdAt': now,
      });
    }
    await batch.commit();
  }
}
