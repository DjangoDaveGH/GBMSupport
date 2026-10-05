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

  /// The feed is limited for UI performance, but the badge must include every
  /// unread alert.
  Stream<int> watchUnreadCount(String userId) {
    return _notifications
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.size);
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

  /// Marks every unread notification about [ticketId] as read for [userId].
  /// Used when a push/local notification is tapped and takes the user
  /// straight to the ticket, bypassing the Notifications screen (whose
  /// own tile tap is the only other place `read` gets flipped) — without
  /// this, the app-icon badge count never comes down for anyone who only
  /// ever opens tickets from the tray notification.
  Future<void> markReadForTicket(String userId, String ticketId) async {
    final snap = await _notifications
        .where('userId', isEqualTo: userId)
        .where('ticketId', isEqualTo: ticketId)
        .where('read', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }
}
