import 'package:hyport/core/models/enums.dart';

/// One category's auto-assignment pool. [useAll] means "every active support
/// handler" (the onTicketCreated Cloud Function resolves that at assign
/// time); otherwise [userIds] is the fixed eligible set.
class CategoryRule {
  final bool useAll;
  final List<String> userIds;

  const CategoryRule({this.useAll = false, this.userIds = const []});

  factory CategoryRule.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CategoryRule();
    if (map['pool'] == 'ALL') return const CategoryRule(useAll: true);
    return CategoryRule(userIds: List<String>.from(map['userIds'] as List? ?? const []));
  }

  Map<String, dynamic> toMap() =>
      useAll ? {'pool': 'ALL'} : {'userIds': userIds};

  CategoryRule copyWith({bool? useAll, List<String>? userIds}) =>
      CategoryRule(useAll: useAll ?? this.useAll, userIds: userIds ?? this.userIds);

  bool get isEmpty => !useAll && userIds.isEmpty;
}

/// Editable mirror of `config/assignment_rules` — what the onTicketCreated
/// Cloud Function reads to auto-assign incoming client tickets by category.
/// Seeded from "GBMSAPP user and roles.docx" by
/// scripts/seed_assignment_rules.js; edited in AssignmentRulesScreen.
class AssignmentRules {
  final bool enabled;
  final Map<TicketCategory, CategoryRule> categories;

  const AssignmentRules({this.enabled = true, this.categories = const {}});

  CategoryRule ruleFor(TicketCategory c) => categories[c] ?? const CategoryRule();

  factory AssignmentRules.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AssignmentRules();
    final rawCats = (map['categories'] as Map?)?.cast<String, dynamic>() ?? const {};
    final categories = <TicketCategory, CategoryRule>{};
    for (final c in TicketCategory.values) {
      final entry = rawCats[c.wireValue];
      if (entry is Map) {
        categories[c] = CategoryRule.fromMap(entry.cast<String, dynamic>());
      }
    }
    return AssignmentRules(
      enabled: map['enabled'] as bool? ?? true,
      categories: categories,
    );
  }

  /// Only the fields this screen owns — `strategy` / `openStatuses` in the
  /// Firestore doc are left untouched (the repository writes with merge).
  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'categories': {
          for (final e in categories.entries) e.key.wireValue: e.value.toMap(),
        },
      };

  AssignmentRules copyWith({bool? enabled, Map<TicketCategory, CategoryRule>? categories}) =>
      AssignmentRules(
        enabled: enabled ?? this.enabled,
        categories: categories ?? this.categories,
      );
}
