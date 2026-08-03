import 'package:cloud_firestore/cloud_firestore.dart';

/// System-level audit log (admin actions: user creation, role changes, etc.)
/// Distinct from TicketActivity, which is the per-ticket audit trail.
class AuditLog {
  final String id;
  final String actorId;
  final String action;
  final String targetType;
  final String targetId;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  const AuditLog({
    required this.id,
    required this.actorId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.metadata,
    required this.timestamp,
  });

  factory AuditLog.fromMap(String id, Map<String, dynamic> map) {
    return AuditLog(
      id: id,
      actorId: map['actorId'] as String,
      action: map['action'] as String,
      targetType: map['targetType'] as String,
      targetId: map['targetId'] as String,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'actorId': actorId,
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'metadata': metadata,
        'timestamp': Timestamp.fromDate(timestamp),
      };
}
