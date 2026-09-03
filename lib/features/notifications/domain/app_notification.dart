import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';

// Named AppNotification to avoid clashing with Flutter's own Notification widget class.
class AppNotification {
  final String id;
  final String userId;
  final String? ticketId;
  final NotificationType type;
  /// Set on admin-broadcast announcements (the admin's free-text topic,
  /// also used as the push notification's title) — null for every
  /// ticket-lifecycle notification, which use a fixed generic title instead.
  final String? title;
  final String message;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    required this.read,
    required this.createdAt,
    this.ticketId,
    this.title,
  });

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      userId: map['userId'] as String? ?? '',
      ticketId: map['ticketId'] as String?,
      type: NotificationType.fromWire(map['type'] as String? ?? 'pending_action'),
      title: map['title'] as String?,
      message: map['message'] as String? ?? '',
      read: map['read'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'ticketId': ticketId,
        'type': type.wireValue,
        'title': title,
        'message': message,
        'read': read,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
