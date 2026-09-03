import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';

class Ticket {
  final String id;
  final String ticketReference;
  final String createdBy;
  final String institutionId;
  final TicketCategory category;
  final String subCategory;
  final String title;
  final String description;
  final List<String> attachmentUrls;
  final TicketPriority priority;
  final TicketImpact impact;
  final bool affectsMultipleUsers;
  final TicketStatus status;
  final String? assignedTo;
  /// Denormalized display name of [assignedTo], written by onTicketUpdated.
  /// Lets the requester see who's handling their ticket without needing read
  /// access to the assignee's `users/{uid}` doc (firestore.rules only lets
  /// support-side roles read other users).
  final String? assignedToName;
  final EscalationLevel escalationLevel;
  final String? resolutionNotes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime? firstRespondedAt;

  const Ticket({
    required this.id,
    required this.ticketReference,
    required this.createdBy,
    required this.institutionId,
    required this.category,
    required this.subCategory,
    required this.title,
    required this.description,
    required this.attachmentUrls,
    required this.priority,
    this.impact = TicketImpact.medium,
    this.affectsMultipleUsers = false,
    required this.status,
    required this.escalationLevel,
    required this.createdAt,
    required this.updatedAt,
    this.assignedTo,
    this.assignedToName,
    this.resolutionNotes,
    this.resolvedAt,
    this.closedAt,
    this.closedBy,
    this.firstRespondedAt,
  });

  factory Ticket.fromMap(String id, Map<String, dynamic> map) {
    return Ticket(
      id: id,
      ticketReference: map['ticketReference'] as String? ?? '',
      createdBy: map['createdBy'] as String? ?? '',
      institutionId: map['institutionId'] as String? ?? '',
      category: TicketCategory.fromWire(map['category'] as String? ?? 'general_enquiry'),
      subCategory: map['subCategory'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      attachmentUrls: List<String>.from(map['attachmentUrls'] as List? ?? []),
      priority: TicketPriority.fromWire(map['priority'] as String? ?? 'medium'),
      impact: TicketImpact.fromWire(map['impact'] as String? ?? 'medium'),
      affectsMultipleUsers: map['affectsMultipleUsers'] as bool? ?? false,
      status: TicketStatus.fromWire(map['status'] as String? ?? 'open'),
      assignedTo: map['assignedTo'] as String?,
      assignedToName: map['assignedToName'] as String?,
      escalationLevel: (map['escalationLevel'] as num?)?.toInt() ?? 0,
      resolutionNotes: map['resolutionNotes'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt: (map['resolvedAt'] as Timestamp?)?.toDate(),
      closedAt: (map['closedAt'] as Timestamp?)?.toDate(),
      closedBy: map['closedBy'] as String?,
      firstRespondedAt: (map['firstRespondedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'ticketReference': ticketReference,
        'createdBy': createdBy,
        'institutionId': institutionId,
        'category': category.wireValue,
        'subCategory': subCategory,
        'title': title,
        'description': description,
        'attachmentUrls': attachmentUrls,
        'priority': priority.wireValue,
        'impact': impact.wireValue,
        'affectsMultipleUsers': affectsMultipleUsers,
        'status': status.wireValue,
        'assignedTo': assignedTo,
        'assignedToName': assignedToName,
        'escalationLevel': escalationLevel,
        'resolutionNotes': resolutionNotes,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
        'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
        'closedBy': closedBy,
        'firstRespondedAt': firstRespondedAt != null ? Timestamp.fromDate(firstRespondedAt!) : null,
      };

  Ticket copyWith({
    TicketCategory? category,
    String? subCategory,
    String? title,
    String? description,
    List<String>? attachmentUrls,
    TicketPriority? priority,
    TicketImpact? impact,
    bool? affectsMultipleUsers,
    TicketStatus? status,
    String? assignedTo,
    String? assignedToName,
    EscalationLevel? escalationLevel,
    String? resolutionNotes,
    DateTime? updatedAt,
    DateTime? resolvedAt,
    DateTime? closedAt,
    String? closedBy,
    DateTime? firstRespondedAt,
  }) {
    return Ticket(
      id: id,
      ticketReference: ticketReference,
      createdBy: createdBy,
      institutionId: institutionId,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      title: title ?? this.title,
      description: description ?? this.description,
      attachmentUrls: attachmentUrls ?? this.attachmentUrls,
      priority: priority ?? this.priority,
      impact: impact ?? this.impact,
      affectsMultipleUsers: affectsMultipleUsers ?? this.affectsMultipleUsers,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      escalationLevel: escalationLevel ?? this.escalationLevel,
      resolutionNotes: resolutionNotes ?? this.resolutionNotes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      firstRespondedAt: firstRespondedAt ?? this.firstRespondedAt,
    );
  }
}
