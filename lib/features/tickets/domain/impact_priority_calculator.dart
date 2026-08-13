import 'package:hyport/core/models/enums.dart';

/// Impact and Priority are no longer picked by the ticket creator (the
/// optimized creation flow dropped that step) — both are auto-assigned from
/// the chosen category instead, visible to Support Coordinator/Functional
/// Lead/Technical Lead/PFM Management on the ticket detail screen. Priority
/// mirrors Impact exactly; `TicketPriority.critical` is deliberately never
/// auto-assigned here — it stays a manual escalation by Support Coordinator+
/// (FR-TCK-12), same as before this change.
class ImpactPriorityCalculator {
  ImpactPriorityCalculator._();

  static const _highImpact = {
    TicketCategory.access,
    TicketCategory.businessRules,
    TicketCategory.reports,
    TicketCategory.budgetForms,
    TicketCategory.dataValidation,
  };

  static const _mediumImpact = {
    TicketCategory.metadata,
    TicketCategory.essbase,
  };

  static TicketImpact deriveImpact(TicketCategory category) {
    if (_highImpact.contains(category)) return TicketImpact.high;
    if (_mediumImpact.contains(category)) return TicketImpact.medium;
    return TicketImpact.low;
  }

  static TicketPriority derivePriority(TicketImpact impact) => switch (impact) {
        TicketImpact.high => TicketPriority.high,
        TicketImpact.medium => TicketPriority.medium,
        TicketImpact.low => TicketPriority.low,
      };
}
