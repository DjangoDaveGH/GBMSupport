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

  // Defaults rather than throws on a missing/malformed field — this is
  // mapped inside a collection .map() (AuditLogRepository.watchRecent()),
  // where one bad document erroring out kills the entire stream, taking
  // down the Audit Logs screen for every admin instead of just that row.
  factory AuditLog.fromMap(String id, Map<String, dynamic> map) {
    return AuditLog(
      id: id,
      actorId: map['actorId'] as String? ?? '',
      action: map['action'] as String? ?? '',
      targetType: map['targetType'] as String? ?? '',
      targetId: map['targetId'] as String? ?? '',
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
