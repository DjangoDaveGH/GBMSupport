import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;
import 'package:intl/intl.dart';
import 'package:hyport/core/widgets/branded_loader.dart';

class TicketDetailScreen extends ConsumerWidget {
  final String ticketId;

  const TicketDetailScreen({super.key, required this.ticketId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketAsync = ref.watch(ticketDetailProvider(ticketId));
    final viewer = ref.watch(currentAppUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: ticketAsync.valueOrNull != null
            ? Text('Ticket #${ticketAsync.valueOrNull!.ticketReference}')
            : const Text('Ticket Details'),
        actions: [
          if (ticketAsync.valueOrNull != null) ...[
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              tooltip: 'Chat',
              onPressed: () => context.push('/tickets/$ticketId/chat'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: TicketStatusChip(status: ticketAsync.valueOrNull!.status)),
            ),
          ],
        ],
      ),
      body: ticketAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Center(child: Text('Could not load ticket: $e')),
        data: (ticket) {
          if (ticket == null) return const Center(child: Text('Ticket not found.'));
          if (viewer == null) return const BrandedLoaderCenter();
          return _TicketDetailBody(ticket: ticket, viewer: viewer);
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _TicketDetailBody extends ConsumerStatefulWidget {
  final Ticket ticket;
  final AppUser viewer;

  const _TicketDetailBody({required this.ticket, required this.viewer});

  @override
  ConsumerState<_TicketDetailBody> createState() => _TicketDetailBodyState();
}

class _TicketDetailBodyState extends ConsumerState<_TicketDetailBody> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  Ticket get ticket => widget.ticket;
  AppUser get viewer => widget.viewer;

  bool get _isOwner => viewer.id == ticket.createdBy;
  bool get _isAssignee => viewer.id == ticket.assignedTo;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.accentBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(categoryIcon(ticket.category), color: AppTheme.accentBlue, size: 21),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ticket.title, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 3),
                              Text('#${ticket.ticketReference}', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (ticket.priority == TicketPriority.critical || ticket.priority == TicketPriority.high) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.flag_rounded, size: 15, color: StatusColors.critical),
                          const SizedBox(width: 6),
                          Text(
                            '${ticket.priority.label} Priority',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: StatusColors.critical),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TicketPriorityChip(priority: ticket.priority),
                        _PlainBadge(label: ticket.category.label),
                        if (ticket.subCategory.isNotEmpty) _PlainBadge(label: ticket.subCategory),
                        if (ticket.escalationLevel > 0)
                          _PlainBadge(label: 'Escalation level ${ticket.escalationLevel}', color: StatusColors.critical),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _HeaderInfoCell(label: 'Category', value: ticket.category.label),
                        ),
                        Expanded(
                          child: _HeaderInfoCell(
                            label: 'Created',
                            value: DateFormat.yMMMd().add_jm().format(ticket.createdAt),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _HeaderInfoCell(
                            label: 'Last Updated',
                            value: DateFormat.yMMMd().add_jm().format(ticket.updatedAt),
                          ),
                        ),
                        Expanded(
                          child: ticket.assignedTo != null
                              ? _AssignedToCell(
                                  userId: ticket.assignedTo!,
                                  fallbackName: ticket.assignedToName,
                                  attemptRead: viewer.role.isSupportSide,
                                )
                              : _HeaderInfoCell(label: 'Assigned To', value: 'Unassigned'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildActions(context, ref),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.navy,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: AppTheme.navy,
            tabs: const [
              Tab(text: 'Timeline'),
              Tab(text: 'Details'),
              Tab(text: 'SLA'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _TimelineTab(ticketId: ticket.id),
              _DetailsTab(ticket: ticket),
              _SlaTab(ticket: ticket),
            ],
          ),
        ),
      ],
    );
  }

  bool get _canAssign => viewer.role == UserRole.supportCoordinator && ticket.status != TicketStatus.closed;

  bool get _canEscalate =>
      (viewer.role == UserRole.supportCoordinator && ticket.status != TicketStatus.closed) ||
      ((viewer.role == UserRole.functionalLead || viewer.role == UserRole.technicalLead) &&
          _isAssignee &&
          ticket.status != TicketStatus.closed &&
          ticket.escalationLevel < 2);

  Widget _buildActions(BuildContext context, WidgetRef ref) {
    if (viewer.role.isSupportSide) return _buildAdminToolbar(context, ref);
    return _buildRequesterActions(context, ref);
  }

  /// Phase 4 mockup screen 22's Add Note/Reassign/Escalate/More toolbar.
  /// "More" is whatever's left of the original role-gated action set below
  /// (Start work/Resolve/Re-escalate/Close) — none of that business logic
  /// changed, only how it's surfaced.
  Widget _buildAdminToolbar(BuildContext context, WidgetRef ref) {
    final overflow = <(String, IconData, VoidCallback)>[];

    if ((viewer.role == UserRole.functionalLead || viewer.role == UserRole.technicalLead) &&
        _isAssignee &&
        ticket.status != TicketStatus.closed) {
      overflow.add(('Start Work', Icons.play_arrow_rounded, () => _showStatusDialog(context, ref, TicketStatus.inProgress)));
      overflow.add((
        'Resolve',
        Icons.check_circle_outline_rounded,
        () => _showStatusDialog(context, ref, TicketStatus.resolved, requireNote: true),
      ));
    }
    if (viewer.role == UserRole.vendorSupport && _isAssignee && ticket.status != TicketStatus.closed) {
      overflow.add((
        'Resolve',
        Icons.check_circle_outline_rounded,
        () => _showStatusDialog(context, ref, TicketStatus.resolved, requireNote: true),
      ));
    }
    if (viewer.role.hasBackOfficeAccess && ticket.status == TicketStatus.resolved && viewer.role != UserRole.pfmManagement) {
      overflow.add((
        'Close Ticket',
        Icons.lock_outline_rounded,
        () => ref.read(ticketRepositoryProvider).close(ticketId: ticket.id, actorId: viewer.id),
      ));
    }

    return Row(
      children: [
        Expanded(
          child: _ToolbarButton(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Chat',
            onTap: () => context.push('/tickets/${ticket.id}/chat'),
          ),
        ),
        if (_canAssign)
          Expanded(
            child: _ToolbarButton(
              icon: Icons.person_add_alt_rounded,
              label: ticket.assignedTo == null ? 'Assign' : 'Reassign',
              onTap: () => context.push('/tickets/${ticket.id}/assign'),
            ),
          ),
        if (_canEscalate)
          Expanded(
            child: _ToolbarButton(icon: Icons.arrow_upward_rounded, label: 'Escalate', onTap: () => _showEscalateDialog(context, ref)),
          ),
        if (overflow.isNotEmpty)
          Expanded(
            child: _ToolbarButton(
              icon: Icons.more_horiz_rounded,
              label: 'More',
              onTap: () => _showMoreSheet(context, overflow),
            ),
          ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context, List<(String, IconData, VoidCallback)> items) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items
              .map((item) => ListTile(
                    leading: Icon(item.$2, color: AppTheme.accentBlue),
                    title: Text(item.$1),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      item.$3();
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildRequesterActions(BuildContext context, WidgetRef ref) {
    final actions = <Widget>[];

    if (_isOwner) {
      if (ticket.status == TicketStatus.resolved) {
        actions.add(FilledButton.icon(
          onPressed: () => ref.read(ticketRepositoryProvider).close(ticketId: ticket.id, actorId: viewer.id),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Confirm & close'),
        ));
        actions.add(OutlinedButton.icon(
          onPressed: () => _showReopenDialog(context, ref),
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('Reopen'),
        ));
      } else if (ticket.status == TicketStatus.closed) {
        actions.add(OutlinedButton.icon(
          onPressed: () => _showReopenDialog(context, ref),
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('Reopen'),
        ));
      }
    }

    actions.add(OutlinedButton.icon(
      onPressed: () => context.push('/tickets/${ticket.id}/chat'),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
      label: const Text('Chat'),
    ));

    return Wrap(spacing: 10, runSpacing: 10, children: actions);
  }

  void _showEscalateDialog(BuildContext context, WidgetRef ref) {
    final noteController = TextEditingController();
    final targetLevel = ticket.escalationLevel < 1 ? 1 : 2;
    showDialog(
      context: context,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final usersAsync = ref.watch(assignableUsersProvider);
        return AlertDialog(
          title: Text(targetLevel == 1 ? 'Escalate to Applications Systems Unit' : 'Escalate to Vendor/Specialist'),
          content: usersAsync.when(
            loading: () => const SizedBox(height: 80, child: BrandedLoaderCenter()),
            error: (e, _) => Text('Could not load users: $e'),
            data: (users) {
              final eligible = users.where((u) {
                if (targetLevel == 1) {
                  // One Applications Systems Unit now — the functional/
                  // technical split no longer maps to distinct people, so
                  // level-1 escalation targets any active APPS member.
                  return u.role == UserRole.functionalLead || u.role == UserRole.technicalLead;
                }
                return u.role == UserRole.vendorSupport;
              }).toList();
              return SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Escalation note (optional)'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    ...eligible.map((u) => ListTile(
                          title: Text(u.name),
                          subtitle: Text(u.role.shortLabel),
                          onTap: () async {
                            await ref.read(ticketRepositoryProvider).escalate(
                                  ticketId: ticket.id,
                                  toLevel: targetLevel,
                                  assigneeId: u.id,
                                  actorId: viewer.id,
                                  note: noteController.text.trim(),
                                );
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        )),
                    if (eligible.isEmpty) const Text('No eligible staff found for this category.'),
                  ],
                ),
              );
            },
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
        );
      }),
    );
  }

  void _showStatusDialog(BuildContext context, WidgetRef ref, TicketStatus newStatus, {bool requireNote = false}) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark as ${newStatus.label}'),
        content: TextField(
          controller: noteController,
          decoration: InputDecoration(labelText: requireNote ? 'Resolution notes' : 'Note (optional)'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (requireNote && noteController.text.trim().isEmpty) return;
              await ref.read(ticketRepositoryProvider).changeStatus(
                    ticketId: ticket.id,
                    from: ticket.status,
                    to: newStatus,
                    actorId: viewer.id,
                    note: noteController.text.trim(),
                  );
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showReopenDialog(BuildContext context, WidgetRef ref) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen ticket'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: 'Why are you reopening this?'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await ref.read(ticketRepositoryProvider).reopen(
                    ticketId: ticket.id,
                    actorId: viewer.id,
                    note: noteController.text.trim(),
                  );
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
  }

}

class _TimelineTab extends ConsumerWidget {
  final String ticketId;

  const _TimelineTab({required this.ticketId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(ticketActivityProvider(ticketId));
    return activityAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load activity: $e')),
      data: (activity) => ListView(
        padding: const EdgeInsets.all(16),
        children: [_ActivityTrail(activity: activity)],
      ),
    );
  }
}

class _DetailsTab extends ConsumerWidget {
  final Ticket ticket;

  const _DetailsTab({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(currentAppUserProvider).valueOrNull;
    final canReassign = viewer != null && viewer.role == UserRole.supportCoordinator && ticket.status != TicketStatus.closed;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (viewer?.role.isSupportSide ?? false) _RequestedByCard(userId: ticket.createdBy),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Description', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(ticket.description, style: Theme.of(context).textTheme.bodyMedium),
              if (ticket.resolutionNotes != null && ticket.resolutionNotes!.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StatusColors.resolved.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: StatusColors.resolved.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.task_alt_rounded, size: 16, color: StatusColors.resolved),
                          const SizedBox(width: 6),
                          Text('Resolution notes',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: StatusColors.resolved)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(ticket.resolutionNotes!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (ticket.assignedTo != null)
          if (viewer?.role.isSupportSide ?? false)
            _AssignedCard(userId: ticket.assignedTo!, ticketId: ticket.id, canReassign: canReassign)
          else
            // Requester: no read access to the assignee's users/{uid} doc,
            // so show the denormalized name from the ticket instead.
            _SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.support_agent_rounded, size: 18, color: AppTheme.accentBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assigned to', style: Theme.of(context).textTheme.labelSmall),
                        Text(ticket.assignedToName ?? 'A support agent', style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ticket information', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              _InfoRow(label: 'Category', value: ticket.category.label),
              if (ticket.subCategory.isNotEmpty) _InfoRow(label: 'Sub-category', value: ticket.subCategory),
              _InfoRow(label: 'Priority', value: ticket.priority.label),
              _InfoRow(label: 'Impact', value: ticket.impact.label),
              _InfoRow(label: 'Status', value: ticket.status.label),
              _InfoRow(label: 'Created', value: DateFormat.yMMMd().add_jm().format(ticket.createdAt)),
              if (ticket.resolvedAt != null) _InfoRow(label: 'Resolved', value: DateFormat.yMMMd().add_jm().format(ticket.resolvedAt!)),
              if (ticket.closedAt != null) _InfoRow(label: 'Closed', value: DateFormat.yMMMd().add_jm().format(ticket.closedAt!)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _AssignedCard extends ConsumerWidget {
  final String userId;
  final String ticketId;
  final bool canReassign;

  const _AssignedCard({required this.userId, required this.ticketId, required this.canReassign});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userByIdProvider(userId));
    return _SectionCard(
      child: userAsync.when(
        loading: () => const SizedBox(height: 44, child: BrandedLoaderCenter()),
        error: (e, _) => Text('Could not load assignee: $e'),
        data: (user) {
          if (user == null) return const Text('Assignee not found.');
          return Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.navy.withValues(alpha: 0.12),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Assigned to', style: Theme.of(context).textTheme.bodySmall),
                    Text(user.name, style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
              if (canReassign)
                TextButton(
                  onPressed: () => context.push('/tickets/$ticketId/assign'),
                  child: const Text('Change'),
                )
              else
                _PlainBadge(label: user.role.shortLabel, color: AppTheme.accentBlue),
            ],
          );
        },
      ),
    );
  }
}

class _PlainBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const _PlainBadge({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c)),
    );
  }
}

/// One cell of the header's Category/Created/Last Updated/Assigned To
/// info grid (mockup screen 15).
class _HeaderInfoCell extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderInfoCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

/// "Assigned To" header cell — same info as [_HeaderInfoCell] but with the
/// assignee's avatar + role, matching the mockup's avatar-led cell.
class _AssignedToCell extends ConsumerWidget {
  final String userId;

  /// Denormalized name from the ticket, used when [attemptRead] is false
  /// (requesters can't read the assignee's user doc) or the read fails.
  final String? fallbackName;

  /// Only support-side viewers may read `users/{uid}`; a requester passes
  /// false here so no denied read is even attempted.
  final bool attemptRead;

  const _AssignedToCell({required this.userId, this.fallbackName, this.attemptRead = true});

  Widget _cell(BuildContext context, String name) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Assigned To', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.navy.withValues(alpha: 0.12),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!attemptRead) return _cell(context, fallbackName ?? 'A support agent');
    final userAsync = ref.watch(userByIdProvider(userId));
    return userAsync.when(
      loading: () => _HeaderInfoCell(label: 'Assigned To', value: fallbackName ?? '…'),
      error: (e, _) => fallbackName != null
          ? _cell(context, fallbackName!)
          : const _HeaderInfoCell(label: 'Assigned To', value: '—'),
      data: (user) {
        if (user == null) return _cell(context, fallbackName ?? 'Unknown');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assigned To', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.navy.withValues(alpha: 0.12),
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// SLA tab (mockup screen 15's 4th tab) — reuses the same SlaCalculator
/// math the Admin Dashboard already shows, so this ticket's numbers always
/// agree with the aggregate ones.
class _SlaTab extends ConsumerWidget {
  final Ticket ticket;

  const _SlaTab({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policyAsync = ref.watch(slaPolicyProvider);
    return policyAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load SLA policy: $e')),
      data: (policy) {
        final targetHours = policy.targetHoursFor(ticket.priority);
        final resolvedAt = ticket.resolvedAt ?? ticket.closedAt;
        final elapsed = (resolvedAt ?? DateTime.now()).difference(ticket.createdAt);
        final elapsedHours = elapsed.inHours;
        final overdue = resolvedAt == null
            ? SlaCalculator.isOverdue(ticket, policy)
            : elapsedHours > targetHours;

        final String statusLabel;
        final Color statusColor;
        if (resolvedAt != null) {
          statusLabel = overdue ? 'Missed SLA' : 'Met SLA';
          statusColor = overdue ? StatusColors.critical : StatusColors.resolved;
        } else if (overdue) {
          statusLabel = 'Overdue';
          statusColor = StatusColors.critical;
        } else {
          statusLabel = 'On Track';
          statusColor = StatusColors.resolved;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 18, color: statusColor),
                      const SizedBox(width: 8),
                      Text('SLA status', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      _PlainBadge(label: statusLabel, color: statusColor),
                    ],
                  ),
                  const Divider(height: 28),
                  _InfoRow(label: 'Priority', value: ticket.priority.label),
                  _InfoRow(label: 'Target window', value: '$targetHours hours'),
                  _InfoRow(
                    label: resolvedAt != null ? 'Time to resolve' : 'Elapsed',
                    value: _formatDuration(elapsed),
                  ),
                  if (resolvedAt == null)
                    _InfoRow(
                      label: overdue ? 'Overdue by' : 'Time remaining',
                      value: _formatDuration(Duration(hours: (elapsedHours - targetHours).abs())),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatDuration(Duration d) {
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  final days = d.inHours ~/ 24;
  final hours = d.inHours % 24;
  return hours == 0 ? '${days}d' : '${days}d ${hours}h';
}

IconData _activityIcon(TicketActivityAction action) => switch (action) {
      TicketActivityAction.created => Icons.add_circle_outline_rounded,
      TicketActivityAction.assigned => Icons.person_add_alt_rounded,
      TicketActivityAction.statusChanged => Icons.sync_alt_rounded,
      TicketActivityAction.escalated => Icons.arrow_upward_rounded,
      TicketActivityAction.commented => Icons.chat_bubble_outline_rounded,
      TicketActivityAction.reopened => Icons.replay_rounded,
      TicketActivityAction.closed => Icons.lock_outline_rounded,
    };

Color _activityColor(TicketActivityAction action) => switch (action) {
      TicketActivityAction.created => AppTheme.accentBlue,
      TicketActivityAction.assigned => StatusColors.assigned,
      TicketActivityAction.statusChanged => AppTheme.accentBlue,
      TicketActivityAction.escalated => StatusColors.critical,
      TicketActivityAction.commented => StatusColors.closed,
      TicketActivityAction.reopened => StatusColors.critical,
      TicketActivityAction.closed => StatusColors.closed,
    };

class _ActivityTrail extends StatelessWidget {
  final List<TicketActivity> activity;

  const _ActivityTrail({required this.activity});

  String _describe(TicketActivity a) {
    switch (a.action) {
      case TicketActivityAction.created:
        return 'Ticket created';
      case TicketActivityAction.assigned:
        return 'Assigned';
      case TicketActivityAction.statusChanged:
        return 'Status changed: ${a.fromValue} → ${a.toValue}';
      case TicketActivityAction.escalated:
        return 'Escalated';
      case TicketActivityAction.commented:
        return 'Chat message';
      case TicketActivityAction.reopened:
        return 'Reopened';
      case TicketActivityAction.closed:
        return 'Closed';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) {
      return Text('No activity yet.', style: Theme.of(context).textTheme.bodyMedium);
    }
    return Column(
      children: [
        for (var i = 0; i < activity.length; i++)
          _TimelineRow(
            isLast: i == activity.length - 1,
            icon: _activityIcon(activity[i].action),
            color: _activityColor(activity[i].action),
            title: _describe(activity[i]),
            note: activity[i].note,
            timestamp: activity[i].timestamp,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final bool isLast;
  final IconData icon;
  final Color color;
  final String title;
  final String? note;
  final DateTime timestamp;

  const _TimelineRow({
    required this.isLast,
    required this.icon,
    required this.color,
    required this.title,
    required this.timestamp,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: color),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: Theme.of(context).colorScheme.outlineVariant)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                      Text(DateFormat.MMMd().add_jm().format(timestamp), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(note!, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestedByCard extends ConsumerWidget {
  final String userId;

  const _RequestedByCard({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userByIdProvider(userId));
    return _SectionCard(
      child: userAsync.when(
        loading: () => const SizedBox(height: 44, child: BrandedLoaderCenter()),
        error: (e, _) => Text('Could not load requester: $e'),
        data: (user) {
          if (user == null) return const Text('Requester not found.');
          // Resolve the requester's specific assembly/MDA name from their
          // institutionId; fall back to the broad MDA/MMDA type while the
          // institution list is still loading or if the id has no match.
          final institutions = ref.watch(institutionListProvider).valueOrNull ?? const [];
          var institutionLabel = user.institutionType.wireValue;
          for (final i in institutions) {
            if (i.id == user.institutionId) {
              institutionLabel = i.name;
              break;
            }
          }
          return Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.12),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Requested By', style: Theme.of(context).textTheme.bodySmall),
                    Text(user.name, style: Theme.of(context).textTheme.titleSmall),
                    Text('${user.role.shortLabel} · $institutionLabel', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppTheme.navy),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.navy),
            ),
          ],
        ),
      ),
    );
  }
}
