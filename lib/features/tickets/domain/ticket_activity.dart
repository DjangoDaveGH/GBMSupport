import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';

/// Sentinel `actorId` for entries written by a Cloud Function rather than a
/// person (e.g. category auto-assignment). No `users/{uid}` doc exists for
/// it — UIs that show an actor render it as "System".
const String systemActorId = 'system';

/// One entry in a ticket's audit trail (subcollection: tickets/{id}/activity).
class TicketActivity {
  final String id;
  final String ticketId;
  final String actorId;
  final TicketActivityAction action;
  final String? fromValue;
  final String? toValue;
  final String? note;
  final String? attachmentUrl;
  final DateTime timestamp;

  const TicketActivity({
    required this.id,
    required this.ticketId,
    required this.actorId,
    required this.action,
    required this.timestamp,
    this.fromValue,
    this.toValue,
    this.note,
    this.attachmentUrl,
  });

  factory TicketActivity.fromMap(String id, Map<String, dynamic> map) {
    return TicketActivity(
      id: id,
      ticketId: map['ticketId'] as String? ?? '',
      actorId: map['actorId'] as String? ?? '',
      action: TicketActivityAction.fromWire(map['action'] as String? ?? 'commented'),
      fromValue: map['fromValue'] as String?,
      toValue: map['toValue'] as String?,
      note: map['note'] as String?,
      attachmentUrl: map['attachmentUrl'] as String?,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'ticketId': ticketId,
        'actorId': actorId,
        'action': action.wireValue,
        'fromValue': fromValue,
        'toValue': toValue,
        'note': note,
        'attachmentUrl': attachmentUrl,
        'timestamp': Timestamp.fromDate(timestamp),
      };
}
