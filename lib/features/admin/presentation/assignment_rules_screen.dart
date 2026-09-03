import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/assignment_rules_providers.dart';
import 'package:hyport/features/config/domain/assignment_rules.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;

/// Edits `config/assignment_rules` — the category → eligible-staff map the
/// onTicketCreated Cloud Function uses to auto-assign incoming client
/// tickets (fewest open tickets, tie-broken by longest-idle). A change here
/// takes effect on the next ticket, no redeploy.
class AssignmentRulesScreen extends ConsumerStatefulWidget {
  const AssignmentRulesScreen({super.key});

  @override
  ConsumerState<AssignmentRulesScreen> createState() => _AssignmentRulesScreenState();
}

/// Roles that can actually be assigned a ticket to handle it — mirrors
/// SUPPORT_ROLES in functions/index.js. Vendor/Specialist is escalation-only
/// and PFM Management can't action tickets, so neither is an assign target.
const _assignableRoles = {
  UserRole.supportCoordinator,
  UserRole.functionalLead,
  UserRole.technicalLead,
};

class _AssignmentRulesScreenState extends ConsumerState<AssignmentRulesScreen> {
  AssignmentRules? _draft;
  bool _saving = false;

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(assignmentRulesRepositoryProvider).update(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignment rules saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setCategory(TicketCategory c, CategoryRule rule) {
    setState(() {
      final cats = Map<TicketCategory, CategoryRule>.from(_draft!.categories);
      cats[c] = rule;
      _draft = _draft!.copyWith(categories: cats);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(assignmentRulesProvider);
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Auto-Assignment')),
      body: rulesAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Center(child: Text('Could not load assignment rules: $e')),
        data: (rules) {
          _draft ??= rules;
          final draft = _draft!;
          final handlers = [
            for (final u in usersAsync.valueOrNull ?? const <AppUser>[])
              if (u.isActive && _assignableRoles.contains(u.role)) u,
          ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          final handlersById = {for (final u in handlers) u.id: u};

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Incoming client tickets are auto-assigned to the least-loaded person in their category’s pool. '
                      'A category with an empty pool falls back to notifying Support Coordinators for manual triage.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: SwitchListTile(
                        value: draft.enabled,
                        onChanged: (v) => setState(() => _draft = draft.copyWith(enabled: v)),
                        title: const Text('Auto-assign incoming tickets'),
                        subtitle: Text(
                          draft.enabled ? 'On — new tickets are routed automatically' : 'Off — every new ticket waits for manual triage',
                        ),
                        activeThumbColor: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Opacity(
                      opacity: draft.enabled ? 1 : 0.5,
                      child: IgnorePointer(
                        ignoring: !draft.enabled,
                        child: Column(
                          children: [
                            for (final c in TicketCategory.values)
                              _CategoryCard(
                                category: c,
                                rule: draft.ruleFor(c),
                                handlers: handlers,
                                handlersById: handlersById,
                                onChanged: (r) => _setCategory(c, r),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Rules'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final TicketCategory category;
  final CategoryRule rule;
  final List<AppUser> handlers;
  final Map<String, AppUser> handlersById;
  final ValueChanged<CategoryRule> onChanged;

  const _CategoryCard({
    required this.category,
    required this.rule,
    required this.handlers,
    required this.handlersById,
    required this.onChanged,
  });

  String get _summary {
    if (rule.useAll) return 'All support staff';
    final known = rule.userIds.where(handlersById.containsKey).length;
    if (known == 0) return 'Nobody — falls back to triage';
    return '$known ${known == 1 ? 'person' : 'people'}';
  }

  @override
  Widget build(BuildContext context) {
    final empty = rule.isEmpty || (!rule.useAll && rule.userIds.where(handlersById.containsKey).isEmpty);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: empty ? StatusColors.critical.withValues(alpha: 0.4) : Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        leading: Icon(categoryIcon(category), size: 20, color: AppTheme.accentBlue),
        title: Text(category.label, style: Theme.of(context).textTheme.bodyMedium),
        subtitle: Text(
          _summary,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: empty ? StatusColors.critical : Colors.black54,
              ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          SwitchListTile(
            dense: true,
            value: rule.useAll,
            onChanged: (v) => onChanged(rule.copyWith(useAll: v)),
            title: const Text('Everyone (all support staff)'),
            activeThumbColor: AppTheme.navy,
          ),
          if (!rule.useAll)
            for (final u in handlers)
              CheckboxListTile(
                dense: true,
                value: rule.userIds.contains(u.id),
                onChanged: (checked) {
                  final ids = List<String>.from(rule.userIds);
                  if (checked == true) {
                    if (!ids.contains(u.id)) ids.add(u.id);
                  } else {
                    ids.remove(u.id);
                  }
                  onChanged(rule.copyWith(userIds: ids));
                },
                title: Text(u.name),
                subtitle: Text(u.role.shortLabel),
                activeColor: AppTheme.navy,
                controlAffinity: ListTileControlAffinity.leading,
              ),
        ],
      ),
    );
  }
}
