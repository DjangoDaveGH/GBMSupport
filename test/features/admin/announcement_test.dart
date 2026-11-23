import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/admin/domain/announcement.dart';
import 'package:hyport/features/notifications/domain/app_notification.dart';

void main() {
  test('Announcement.fromMap reads a stored announcement', () {
    final a = Announcement.fromMap('abc', {
      'type': 'maintenance',
      'topic': 'Planned Maintenance',
      'message': 'Offline Saturday',
      'audience': 'mmda',
      'attachmentUrls': ['https://x/a.pdf'],
      'createdBy': 'admin1',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 23, 9)),
      'updatedAt': null,
      'recipientCount': 12,
      'status': 'sent',
    });
    expect(a.type, NotificationType.maintenance);
    expect(a.audience, AnnouncementAudience.mmda);
    expect(a.attachmentUrls, ['https://x/a.pdf']);
    expect(a.recipientCount, 12);
    expect(a.isEdited, isFalse);
    expect(a.createdAt, DateTime(2026, 11, 23, 9));
  });

  test('Announcement.fromMap tolerates missing fields', () {
    final a = Announcement.fromMap('abc', const {});
    expect(a.audience, AnnouncementAudience.all);
    expect(a.attachmentUrls, isEmpty);
    expect(a.status, 'sent');
  });

  test('AppNotification reads announcement fields, defaults for others', () {
    final n = AppNotification.fromMap('n1', {
      'userId': 'u1',
      'type': 'system_downtime',
      'title': 'Downtime',
      'message': 'm',
      'read': false,
      'announcementId': 'abc',
      'attachmentUrls': ['https://x/a.png', 42],
      'edited': true,
    });
    expect(n.announcementId, 'abc');
    expect(n.attachmentUrls, ['https://x/a.png']);
    expect(n.edited, isTrue);

    final ticket = AppNotification.fromMap('n2', {
      'userId': 'u1',
      'type': 'assigned',
      'message': 'm',
    });
    expect(ticket.announcementId, isNull);
    expect(ticket.attachmentUrls, isEmpty);
    expect(ticket.edited, isFalse);
  });
}
