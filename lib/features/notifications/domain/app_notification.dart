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

  /// Set on admin announcements (links to announcements/{id}); the
  /// announcement's files, and whether the admin edited it after sending.
  final String? announcementId;
  final List<String> attachmentUrls;
  final bool edited;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    required this.read,
    required this.createdAt,
    this.ticketId,
    this.title,
    this.announcementId,
    this.attachmentUrls = const [],
    this.edited = false,
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
      createdAt: _readCreatedAt(map['createdAt']),
      announcementId: map['announcementId'] as String?,
      attachmentUrls:
          (map['attachmentUrls'] as List?)?.whereType<String>().toList() ??
          const [],
      edited: map['edited'] as bool? ?? false,
    );
  }

  static DateTime _readCreatedAt(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
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
