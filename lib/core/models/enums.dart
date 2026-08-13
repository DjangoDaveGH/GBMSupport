/// Shared enums used across features. Kept as plain Dart enums (not
/// freezed/json_serializable-backed) with explicit string<->enum mapping so
/// Firestore documents store readable strings, not enum indices.
library;

enum UserRole {
  mdaUser,
  focalPerson,
  supportCoordinator,
  functionalLead,
  technicalLead,
  pfmManagement,
  vendorSupport;

  String get wireValue => switch (this) {
        UserRole.mdaUser => 'mda_user',
        UserRole.focalPerson => 'focal_person',
        UserRole.supportCoordinator => 'support_coordinator',
        UserRole.functionalLead => 'functional_lead',
        UserRole.technicalLead => 'technical_lead',
        UserRole.pfmManagement => 'pfm_management',
        UserRole.vendorSupport => 'vendor_support',
      };

  static UserRole fromWire(String value) => switch (value) {
        'mda_user' => UserRole.mdaUser,
        'focal_person' => UserRole.focalPerson,
        'support_coordinator' => UserRole.supportCoordinator,
        'functional_lead' => UserRole.functionalLead,
        'technical_lead' => UserRole.technicalLead,
        'pfm_management' => UserRole.pfmManagement,
        'vendor_support' => UserRole.vendorSupport,
        _ => throw ArgumentError('Unknown UserRole: $value'),
      };

  String get label => switch (this) {
        UserRole.mdaUser => 'MDA/MMDA User',
        UserRole.focalPerson => 'MDA/MMDA Focal Person',
        UserRole.supportCoordinator => 'Support Coordinator',
        UserRole.functionalLead => 'Functional Lead',
        UserRole.technicalLead => 'Technical Lead',
        UserRole.pfmManagement => 'PFM-Systems Division / Management',
        UserRole.vendorSupport => 'Vendor/Specialist Support',
      };

  /// Roles that can see tickets beyond their own institution — Coordinator,
  /// Functional/Technical Lead, Management, **and** Vendor/Specialist
  /// (whose visibility is narrowed further to only what's escalated to them
  /// — see TicketRepository.scopedQuery). Used for home-screen layout choice
  /// (stat-card view vs. "your open tickets" + new-ticket FAB) and similar
  /// "is this a support-handling account at all" checks.
  bool get isSupportSide => this != UserRole.mdaUser && this != UserRole.focalPerson;

  /// Narrower than [isSupportSide]: Coordinator/Leads/Management only —
  /// mirrors firestore.rules' `isSupportSide()` exactly. Vendor/Specialist
  /// is deliberately excluded here even though [isSupportSide] includes it,
  /// because Section 3 caps Vendor at "resolve or re-escalate" — no
  /// dashboard, no knowledge-base editing, no closing tickets. Use this for
  /// any permission beyond "can see a ticket handed to them."
  bool get hasBackOfficeAccess => switch (this) {
        UserRole.supportCoordinator || UserRole.functionalLead || UserRole.technicalLead || UserRole.pfmManagement => true,
        UserRole.mdaUser || UserRole.focalPerson || UserRole.vendorSupport => false,
      };
}

enum InstitutionType {
  mda,
  mmda;

  String get wireValue => this == InstitutionType.mda ? 'MDA' : 'MMDA';

  static InstitutionType fromWire(String value) =>
      value == 'MDA' ? InstitutionType.mda : InstitutionType.mmda;
}

enum TicketCategory {
  access,
  workflow,
  budgetForms,
  reports,
  smartView,
  businessRules,
  metadata,
  dataValidation,
  essbase,
  systemPerformance,
  mobileAppIssue,
  generalEnquiry;

  String get wireValue => switch (this) {
        TicketCategory.access => 'access',
        TicketCategory.workflow => 'workflow',
        TicketCategory.budgetForms => 'budget_forms',
        TicketCategory.reports => 'reports',
        TicketCategory.smartView => 'smart_view',
        TicketCategory.businessRules => 'business_rules',
        TicketCategory.metadata => 'metadata',
        TicketCategory.dataValidation => 'data_validation',
        TicketCategory.essbase => 'essbase',
        TicketCategory.systemPerformance => 'system_performance',
        TicketCategory.mobileAppIssue => 'mobile_app_issue',
        TicketCategory.generalEnquiry => 'general_enquiry',
      };

  static TicketCategory fromWire(String value) =>
      TicketCategory.values.firstWhere((c) => c.wireValue == value,
          orElse: () => TicketCategory.generalEnquiry);

  String get label => switch (this) {
        TicketCategory.access => 'Access',
        TicketCategory.workflow => 'Workflow',
        TicketCategory.budgetForms => 'Budget Forms',
        TicketCategory.reports => 'Reports',
        TicketCategory.smartView => 'Smart View',
        TicketCategory.businessRules => 'Business Rules',
        TicketCategory.metadata => 'Metadata',
        TicketCategory.dataValidation => 'Data Validation',
        TicketCategory.essbase => 'Essbase',
        TicketCategory.systemPerformance => 'System Performance',
        TicketCategory.mobileAppIssue => 'Mobile App Issue',
        TicketCategory.generalEnquiry => 'General Enquiry',
      };

  /// Functional issues route to a Functional Lead on escalation; the rest
  /// (metadata, security/access, business rules, essbase, integration/perf)
  /// route to a Technical Lead. See DECISIONS.md.
  bool get isFunctional => switch (this) {
        TicketCategory.workflow ||
        TicketCategory.budgetForms ||
        TicketCategory.reports ||
        TicketCategory.smartView ||
        TicketCategory.dataValidation ||
        TicketCategory.generalEnquiry ||
        TicketCategory.mobileAppIssue =>
          true,
        TicketCategory.access ||
        TicketCategory.businessRules ||
        TicketCategory.metadata ||
        TicketCategory.essbase ||
        TicketCategory.systemPerformance =>
          false,
      };
}

enum TicketImpact {
  low,
  medium,
  high;

  String get wireValue => name;

  static TicketImpact fromWire(String value) => TicketImpact.values
      .firstWhere((i) => i.wireValue == value, orElse: () => TicketImpact.medium);

  String get label => switch (this) {
        TicketImpact.low => 'Low',
        TicketImpact.medium => 'Medium',
        TicketImpact.high => 'High',
      };
}

enum TicketPriority {
  critical,
  high,
  medium,
  low;

  String get wireValue => name;

  static TicketPriority fromWire(String value) => TicketPriority.values
      .firstWhere((p) => p.wireValue == value, orElse: () => TicketPriority.medium);

  String get label => switch (this) {
        TicketPriority.critical => 'Critical',
        TicketPriority.high => 'High',
        TicketPriority.medium => 'Medium',
        TicketPriority.low => 'Low',
      };
}

enum TicketStatus {
  open,
  assigned,
  inProgress,
  escalated,
  resolved,
  reopened,
  closed;

  String get wireValue => switch (this) {
        TicketStatus.open => 'open',
        TicketStatus.assigned => 'assigned',
        TicketStatus.inProgress => 'in_progress',
        TicketStatus.escalated => 'escalated',
        TicketStatus.resolved => 'resolved',
        TicketStatus.reopened => 'reopened',
        TicketStatus.closed => 'closed',
      };

  static TicketStatus fromWire(String value) =>
      TicketStatus.values.firstWhere((s) => s.wireValue == value,
          orElse: () => TicketStatus.open);

  String get label => switch (this) {
        TicketStatus.open => 'Open',
        TicketStatus.assigned => 'Assigned',
        TicketStatus.inProgress => 'In Progress',
        TicketStatus.escalated => 'Escalated',
        TicketStatus.resolved => 'Resolved',
        TicketStatus.reopened => 'Reopened',
        TicketStatus.closed => 'Closed',
      };

  bool get isOpenState => this != TicketStatus.closed;
}

/// escalationLevel: 0 = none, 1 = functional/technical lead, 2 = vendor/specialist
typedef EscalationLevel = int;

enum ArticleStatus {
  draft,
  review,
  published;

  String get wireValue => name;

  static ArticleStatus fromWire(String value) =>
      ArticleStatus.values.firstWhere((s) => s.wireValue == value, orElse: () => ArticleStatus.draft);

  String get label => switch (this) {
        ArticleStatus.draft => 'Draft',
        ArticleStatus.review => 'Review',
        ArticleStatus.published => 'Published',
      };
}

enum TicketActivityAction {
  created,
  assigned,
  statusChanged,
  escalated,
  commented,
  reopened,
  closed;

  String get wireValue => switch (this) {
        TicketActivityAction.created => 'created',
        TicketActivityAction.assigned => 'assigned',
        TicketActivityAction.statusChanged => 'status_changed',
        TicketActivityAction.escalated => 'escalated',
        TicketActivityAction.commented => 'commented',
        TicketActivityAction.reopened => 'reopened',
        TicketActivityAction.closed => 'closed',
      };

  static TicketActivityAction fromWire(String value) =>
      TicketActivityAction.values.firstWhere((a) => a.wireValue == value,
          orElse: () => TicketActivityAction.commented);
}

enum NotificationType {
  ticketReceived,
  assigned,
  escalated,
  pendingAction,
  resolved,
  systemDowntime,
  deadlineReminder,
  maintenance,
  chatMessage;

  String get wireValue => switch (this) {
        NotificationType.ticketReceived => 'ticket_received',
        NotificationType.assigned => 'assigned',
        NotificationType.escalated => 'escalated',
        NotificationType.pendingAction => 'pending_action',
        NotificationType.resolved => 'resolved',
        NotificationType.systemDowntime => 'system_downtime',
        NotificationType.deadlineReminder => 'deadline_reminder',
        NotificationType.maintenance => 'maintenance',
        NotificationType.chatMessage => 'commented',
      };

  static NotificationType fromWire(String value) =>
      NotificationType.values.firstWhere((t) => t.wireValue == value,
          orElse: () => NotificationType.pendingAction);
}
