import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';

/// Who an announcement goes to. See functions/index.js's
/// matchesBroadcastAudience for the exact server-side matching.
enum AnnouncementAudience {
  all('all', 'All Users'),
  mda('mda', 'MDA Users'),
  mmda('mmda', 'MMDA Users'),
  staff('staff', 'Staff (Support / Admin)');

  final String wireValue;
  final String label;

  const AnnouncementAudience(this.wireValue, this.label);

  static AnnouncementAudience fromWire(String? value) => values.firstWhere(
    (a) => a.wireValue == value,
    orElse: () => AnnouncementAudience.all,
  );
}

/// The categories an admin can send an announcement under.
const announcementTypes = [
  NotificationType.systemDowntime,
  NotificationType.maintenance,
  NotificationType.deadlineReminder,
];

String announcementTypeLabel(NotificationType type) => switch (type) {
  NotificationType.systemDowntime => 'System Downtime',
  NotificationType.maintenance => 'Planned Maintenance',
  NotificationType.deadlineReminder => 'Deadline Reminder',
  _ => type.wireValue,
};

/// A sent announcement, stored in `announcements/{id}` by the
/// adminBroadcastNotification callable. Each recipient also gets a copy in
/// their own `notifications` docs (linked by `announcementId`), which the
/// edit/delete callables keep in sync.
class Announcement {
  final String id;
  final NotificationType type;
  final String topic;
  final String message;
  final AnnouncementAudience audience;
  final List<String> attachmentUrls;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int recipientCount;
  final String status;

  const Announcement({
    required this.id,
    required this.type,
    required this.topic,
    required this.message,
    required this.audience,
    required this.attachmentUrls,
    required this.createdBy,
    required this.createdAt,
    required this.recipientCount,
    required this.status,
    this.updatedAt,
  });

  bool get isEdited => updatedAt != null;

  factory Announcement.fromMap(String id, Map<String, dynamic> map) {
    DateTime? readDate(Object? v) => v is Timestamp ? v.toDate() : null;
    return Announcement(
      id: id,
      type: NotificationType.fromWire(map['type'] as String? ?? ''),
      topic: map['topic'] as String? ?? '',
      message: map['message'] as String? ?? '',
      audience: AnnouncementAudience.fromWire(map['audience'] as String?),
      attachmentUrls: (map['attachmentUrls'] as List?)?.cast<String>() ?? const [],
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: readDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: readDate(map['updatedAt']),
      recipientCount: (map['recipientCount'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'sent',
    );
  }
}
