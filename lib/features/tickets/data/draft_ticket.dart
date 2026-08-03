import 'package:hyport/core/models/enums.dart';

/// A ticket created while fully offline, queued locally until connectivity
/// returns. Stored in a Hive `Box<Map>` (dynamic box, no generated
/// TypeAdapter needed) keyed by [localId]. See DECISIONS.md for why this
/// exists alongside Firestore's own offline write queue: Firestore queues
/// writes to documents it already knows the path for, but a brand-new
/// ticket still needs a human-readable reference generated via a Firestore
/// transaction, which requires connectivity. Drafts hold the ticket content
/// until that transaction can run.
class DraftTicket {
  final String localId;
  final String createdBy;
  final String institutionId;
  final TicketCategory category;
  final String subCategory;
  final String title;
  final String description;
  final List<String> localAttachmentPaths;
  final TicketPriority priority;
  final TicketImpact impact;
  final bool affectsMultipleUsers;
  final DateTime createdAt;
  final bool pendingSync;

  const DraftTicket({
    required this.localId,
    required this.createdBy,
    required this.institutionId,
    required this.category,
    required this.subCategory,
    required this.title,
    required this.description,
    required this.localAttachmentPaths,
    required this.priority,
    this.impact = TicketImpact.medium,
    this.affectsMultipleUsers = false,
    required this.createdAt,
    this.pendingSync = true,
  });

  factory DraftTicket.fromMap(Map<dynamic, dynamic> map) {
    return DraftTicket(
      localId: map['localId'] as String,
      createdBy: map['createdBy'] as String,
      institutionId: map['institutionId'] as String,
      category: TicketCategory.fromWire(map['category'] as String),
      subCategory: map['subCategory'] as String? ?? '',
      title: map['title'] as String,
      description: map['description'] as String,
      localAttachmentPaths: List<String>.from(map['localAttachmentPaths'] as List? ?? []),
      priority: TicketPriority.fromWire(map['priority'] as String? ?? 'medium'),
      impact: TicketImpact.fromWire(map['impact'] as String? ?? 'medium'),
      affectsMultipleUsers: map['affectsMultipleUsers'] as bool? ?? false,
      createdAt: DateTime.parse(map['createdAt'] as String),
      pendingSync: map['pendingSync'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'localId': localId,
        'createdBy': createdBy,
        'institutionId': institutionId,
        'category': category.wireValue,
        'subCategory': subCategory,
        'title': title,
        'description': description,
        'localAttachmentPaths': localAttachmentPaths,
        'priority': priority.wireValue,
        'impact': impact.wireValue,
        'affectsMultipleUsers': affectsMultipleUsers,
        'createdAt': createdAt.toIso8601String(),
        'pendingSync': pendingSync,
      };
}
