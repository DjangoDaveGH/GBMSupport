import 'package:hyport/core/models/enums.dart';

/// Per-priority target resolution windows, in hours. Stored as a single
/// `config/sla` Firestore doc (editable via the admin Settings screen) so
/// "SLA Compliance" and "Overdue" in Analytics/Dashboard are computed
/// against a real, admin-controlled policy rather than a hardcoded guess.
class SlaPolicy {
  final int criticalHours;
  final int highHours;
  final int mediumHours;
  final int lowHours;

  const SlaPolicy({
    this.criticalHours = 4,
    this.highHours = 24,
    this.mediumHours = 72,
    this.lowHours = 120,
  });

  factory SlaPolicy.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SlaPolicy();
    return SlaPolicy(
      criticalHours: (map['criticalHours'] as num?)?.toInt() ?? 4,
      highHours: (map['highHours'] as num?)?.toInt() ?? 24,
      mediumHours: (map['mediumHours'] as num?)?.toInt() ?? 72,
      lowHours: (map['lowHours'] as num?)?.toInt() ?? 120,
    );
  }

  Map<String, dynamic> toMap() => {
        'criticalHours': criticalHours,
        'highHours': highHours,
        'mediumHours': mediumHours,
        'lowHours': lowHours,
      };

  int targetHoursFor(TicketPriority priority) => switch (priority) {
        TicketPriority.critical => criticalHours,
        TicketPriority.high => highHours,
        TicketPriority.medium => mediumHours,
        TicketPriority.low => lowHours,
      };

  SlaPolicy copyWith({int? criticalHours, int? highHours, int? mediumHours, int? lowHours}) => SlaPolicy(
        criticalHours: criticalHours ?? this.criticalHours,
        highHours: highHours ?? this.highHours,
        mediumHours: mediumHours ?? this.mediumHours,
        lowHours: lowHours ?? this.lowHours,
      );
}
