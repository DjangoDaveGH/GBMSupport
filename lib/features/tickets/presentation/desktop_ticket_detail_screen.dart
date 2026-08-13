import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';
import 'package:intl/intl.dart';

/// Phase 5 mockup screen 32 — same ticket/activity/SLA data as the mobile
/// Ticket Detail, laid out as a two-column web page (main content + info
/// sidebar) with an "Actions" menu instead of a bottom toolbar. Calls the
/// exact same TicketRepository methods as the mobile version; only the
/// chrome around them differs.
class DesktopTicketDetailScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const DesktopTicketDetailScreen({super.key, required this.ticketId});

  @override
  ConsumerState<DesktopTicketDetailScreen> createState() => _DesktopTicketDetailScreenState();
}

class _DesktopTicketDetailScreenState extends ConsumerState<DesktopTicketDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);
  final _noteController = TextEditingController();
  final _actionsButtonKey = GlobalKey();

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketDetailProvider(widget.ticketId));
    final viewer = ref.watch(currentAppUserProvider).valueOrNull;

    return ticketAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load ticket: $e')),
      data: (ticket) {
        if (ticket == null) return const Center(child: Text('Ticket not found.'));
        if (viewer == null) return const BrandedLoaderCenter();
        return _buildBody(context, ticket, viewer);
      },
    );
  }

  Widget _buildBody(BuildContext context, Ticket ticket, AppUser viewer) {
    final isAssignee = viewer.id == ticket.assignedTo;
    final canAssign = viewer.role == UserRole.supportCoordinator && ticket.status != TicketStatus.closed;
    final canEscalate = (viewer.role == UserRole.supportCoordinator && ticket.status != TicketStatus.closed) ||
        ((viewer.role == UserRole.functionalLead || viewer.role == UserRole.technicalLead) &&
            isAssignee &&
            ticket.status != TicketStatus.closed &&
            ticket.escalationLevel < 2);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TextButton(onPressed: () => context.pop(), child: const Text('← Tickets')),
              Text(' / #${ticket.ticketReference}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
              const Spacer(),
              // Plain FilledButton/FilledButton.icon silently fails to paint
              // here (repro'd: TextButton renders fine in the same spot,
              // FilledButton never does, with or without an icon/closure) —
              // this Row doesn't get a tightly-bounded width from its Column
              // ancestor (no crossAxisAlignment.stretch upstream), and
              // FilledButton's internal Material/ink layout needs one.
              // IntrinsicWidth forces a two-pass measure so the button gets
              // a concrete size regardless, without changing its appearance.
              IntrinsicWidth(
                child: FilledButton.icon(
                  key: _actionsButtonKey,
                  onPressed: () => _showActionsMenu(context, ticket, viewer, isAssignee, canAssign, canEscalate),
                  icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  label: const Text('Actions'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _MainColumn(ticket: ticket, tabController: _tabController, noteController: _noteController)),
                const SizedBox(width: 20),
                Expanded(flex: 1, child: SingleChildScrollView(child: _SidebarColumn(ticket: ticket))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showActionsMenu(
    BuildContext context,
    Ticket ticket,
    AppUser viewer,
    bool isAssignee,
    bool canAssign,
    bool canEscalate,
  ) {
    final button = _actionsButtonKey.currentContext!.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<void>(
      context: context,
      position: position,
      items: [
        if (canAssign)
          PopupMenuItem(
            onTap: () => context.push('/tickets/${ticket.id}/assign'),
            child: Text(ticket.assignedTo == null ? 'Assign' : 'Reassign'),
          ),
        if (canEscalate) PopupMenuItem(onTap: () => _showEscalateDialog(context, ticket, viewer), child: const Text('Escalate')),
        if ((viewer.role == UserRole.functionalLead || viewer.role == UserRole.technicalLead) &&
            isAssignee &&
            ticket.status != TicketStatus.closed) ...[
          PopupMenuItem(
            onTap: () => _changeStatus(ticket, viewer, TicketStatus.inProgress),
            child: const Text('Start Work'),
          ),
          PopupMenuItem(
            onTap: () => _showResolveDialog(context, ticket, viewer),
            child: const Text('Resolve'),
          ),
        ],
        if (viewer.role == UserRole.vendorSupport && isAssignee && ticket.status != TicketStatus.closed)
          PopupMenuItem(onTap: () => _showResolveDialog(context, ticket, viewer), child: const Text('Resolve')),
        if (viewer.role.hasBackOfficeAccess && ticket.status == TicketStatus.resolved && viewer.role != UserRole.pfmManagement)
          PopupMenuItem(
            onTap: () => ref.read(ticketRepositoryProvider).close(ticketId: ticket.id, actorId: viewer.id),
            child: const Text('Close Ticket'),
          ),
        PopupMenuItem(onTap: () => _showCommentDialog(context, ticket, viewer), child: const Text('Add Chat Message')),
      ],
    );
  }

  Future<void> _changeStatus(Ticket ticket, AppUser viewer, TicketStatus status) {
    return ref.read(ticketRepositoryProvider).changeStatus(
          ticketId: ticket.id,
          from: ticket.status,
          to: status,
          actorId: viewer.id,
        );
  }

  void _showEscalateDialog(BuildContext context, Ticket ticket, AppUser viewer) {
    final targetLevel = ticket.escalationLevel < 1 ? 1 : 2;
    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(builder: (dialogContext, ref, _) {
        final usersAsync = ref.watch(assignableUsersProvider);
        return AlertDialog(
          title: Text(targetLevel == 1 ? 'Escalate to Functional/Technical Lead' : 'Escalate to Vendor/Specialist'),
          content: usersAsync.when(
            loading: () => const SizedBox(height: 80, child: BrandedLoaderCenter()),
            error: (e, _) => Text('Could not load users: $e'),
            data: (users) {
              final eligible = users.where((u) {
                if (targetLevel == 1) {
                  return ticket.category.isFunctional ? u.role == UserRole.functionalLead : u.role == UserRole.technicalLead;
                }
                return u.role == UserRole.vendorSupport;
              }).toList();
              return SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: eligible
                      .map((u) => ListTile(
                            title: Text(u.name),
                            subtitle: Text(u.role.label),
                            onTap: () async {
                              await ref.read(ticketRepositoryProvider).escalate(
                                    ticketId: ticket.id,
                                    toLevel: targetLevel,
                                    assigneeId: u.id,
                                    actorId: viewer.id,
                                  );
                              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                            },
                          ))
                      .toList(),
                ),
              );
            },
          ),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel'))],
        );
      }),
    );
  }

  void _showResolveDialog(BuildContext context, Ticket ticket, AppUser viewer) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve Ticket'),
        content: TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Resolution notes'), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (noteController.text.trim().isEmpty) return;
              await ref.read(ticketRepositoryProvider).changeStatus(
                    ticketId: ticket.id,
                    from: ticket.status,
                    to: TicketStatus.resolved,
                    actorId: viewer.id,
                    note: noteController.text.trim(),
                  );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showCommentDialog(BuildContext context, Ticket ticket, AppUser viewer) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Chat Message'),
        content: TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Message'), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (noteController.text.trim().isEmpty) return;
              await ref.read(ticketRepositoryProvider).addComment(ticketId: ticket.id, actorId: viewer.id, note: noteController.text.trim());
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}

class _MainColumn extends ConsumerWidget {
  final Ticket ticket;
  final TabController tabController;
  final TextEditingController noteController;

  const _MainColumn({required this.ticket, required this.tabController, required this.noteController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ticket.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  TicketStatusChip(status: ticket.status),
                  TicketPriorityChip(priority: ticket.priority),
                  _PlainBadge(label: ticket.category.label),
                ]),
                const SizedBox(height: 16),
                Text(ticket.description, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
            child: TabBar(
              controller: tabController,
              isScrollable: true,
              labelColor: AppTheme.navy,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              indicatorColor: AppTheme.navy,
              tabs: const [Tab(text: 'Timeline'), Tab(text: 'Chat'), Tab(text: 'Details'), Tab(text: 'SLA')],
              // Chat is a full dedicated page (same one mobile uses), not an
              // inline pane like the other three tabs — TabController.animateTo
              // has already run by the time onTap fires, so this snaps the
              // selection straight back before pushing, rather than leaving
              // "Chat" highlighted over its (now-unused) inline pane.
              onTap: (index) {
                if (index == 1) {
                  tabController.index = tabController.previousIndex;
                  context.push('/tickets/${ticket.id}/chat');
                }
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                _TimelineView(ticketId: ticket.id),
                _ConversationView(ticketId: ticket.id),
                _DetailsView(ticket: ticket),
                _SlaView(ticket: ticket),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: noteController,
                    decoration: const InputDecoration(hintText: 'Add internal note...'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () async {
                    final viewer = ref.read(currentAppUserProvider).valueOrNull;
                    if (viewer == null || noteController.text.trim().isEmpty) return;
                    await ref.read(ticketRepositoryProvider).addComment(
                          ticketId: ticket.id,
                          actorId: viewer.id,
                          note: noteController.text.trim(),
                        );
                    noteController.clear();
                  },
                  child: const Text('Update Status'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

String _describeActivity(TicketActivity a) {
  switch (a.action) {
    case TicketActivityAction.created:
      return 'Ticket Created';
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

class _TimelineView extends ConsumerWidget {
  final String ticketId;

  const _TimelineView({required this.ticketId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(ticketActivityProvider(ticketId));
    return activityAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load timeline: $e')),
      data: (activity) {
        if (activity.isEmpty) return const Center(child: Text('No activity yet.'));
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: activity.length,
          itemBuilder: (context, i) {
            final a = activity[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: _activityColor(a.action).withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(_activityIcon(a.action), size: 15, color: _activityColor(a.action)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(_describeActivity(a), style: Theme.of(context).textTheme.titleSmall)),
                            Text(DateFormat.MMMd().add_jm().format(a.timestamp), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        if (a.note != null && a.note!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(a.note!, style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ConversationView extends ConsumerWidget {
  final String ticketId;

  const _ConversationView({required this.ticketId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(ticketActivityProvider(ticketId));
    return activityAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load comments: $e')),
      data: (activity) {
        final comments = activity.where((a) => a.action == TicketActivityAction.commented).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (comments.isEmpty) return const Center(child: Text('No chat messages yet.'));
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: comments.length,
          itemBuilder: (context, i) {
            final c = comments[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.note ?? '', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(DateFormat.MMMd().add_jm().format(c.timestamp), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DetailsView extends StatelessWidget {
  final Ticket ticket;

  const _DetailsView({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _InfoRow(label: 'Category', value: ticket.category.label),
        if (ticket.subCategory.isNotEmpty) _InfoRow(label: 'Sub-category', value: ticket.subCategory),
        _InfoRow(label: 'Priority', value: ticket.priority.label),
        _InfoRow(label: 'Impact', value: ticket.impact.label),
        _InfoRow(label: 'Status', value: ticket.status.label),
        _InfoRow(label: 'Escalation Level', value: '${ticket.escalationLevel}'),
        _InfoRow(label: 'Created', value: DateFormat.yMMMd().add_jm().format(ticket.createdAt)),
        if (ticket.resolutionNotes != null && ticket.resolutionNotes!.isNotEmpty) _InfoRow(label: 'Resolution Notes', value: ticket.resolutionNotes!),
      ],
    );
  }
}

class _SlaView extends ConsumerWidget {
  final Ticket ticket;

  const _SlaView({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();
    final targetHours = policy.targetHoursFor(ticket.priority);
    final due = ticket.createdAt.add(Duration(hours: targetHours));
    final resolvedAt = ticket.resolvedAt ?? ticket.closedAt;
    final met = resolvedAt != null ? SlaCalculator.metSla(ticket, policy) : null;
    final overdue = SlaCalculator.isOverdue(ticket, policy);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _InfoRow(label: 'Target Resolution Window', value: '$targetHours hours (${ticket.priority.label})'),
        _InfoRow(label: 'SLA Due', value: DateFormat.yMMMd().add_jm().format(due)),
        if (resolvedAt != null)
          _InfoRow(
            label: 'Resolved',
            value: '${DateFormat.yMMMd().add_jm().format(resolvedAt)} · ${met! ? 'Within SLA' : 'Breached SLA'}',
          )
        else
          _InfoRow(label: 'Current Status', value: overdue ? 'Overdue' : 'Within SLA'),
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _SidebarColumn extends ConsumerWidget {
  final Ticket ticket;

  const _SidebarColumn({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();
    final due = ticket.createdAt.add(Duration(hours: policy.targetHoursFor(ticket.priority)));

    return Column(
      children: [
        _SidebarCard(
          title: 'Ticket Information',
          child: Column(
            children: [
              _InfoRow(label: 'ID', value: ticket.ticketReference),
              _InfoRow(label: 'Status', value: ticket.status.label),
              _InfoRow(label: 'Priority', value: ticket.priority.label),
              _InfoRow(label: 'Category', value: ticket.category.label),
              _InfoRow(label: 'Created', value: DateFormat.yMMMd().format(ticket.createdAt)),
              _InfoRow(label: 'Last Updated', value: DateFormat.yMMMd().format(ticket.updatedAt)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (ticket.assignedTo != null)
          _SidebarCard(
            title: 'Assigned To',
            child: _AssigneeInfo(userId: ticket.assignedTo!),
          ),
        const SizedBox(height: 16),
        _SidebarCard(
          title: 'SLA Due',
          child: Row(
            children: [
              const Icon(Icons.event_outlined, size: 16, color: AppTheme.accentBlue),
              const SizedBox(width: 8),
              Text(DateFormat.yMMMd().add_jm().format(due), style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SidebarCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AssigneeInfo extends ConsumerWidget {
  final String userId;

  const _AssigneeInfo({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userByIdProvider(userId));
    return userAsync.when(
      loading: () => const SizedBox(height: 40, child: BrandedLoaderCenter()),
      error: (e, _) => Text('Could not load: $e'),
      data: (user) {
        if (user == null) return const Text('Not found.');
        return Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
              child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: Theme.of(context).textTheme.titleSmall),
                  Text(user.role.label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlainBadge extends StatelessWidget {
  final String label;

  const _PlainBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppTheme.ink.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.ink)),
    );
  }
}
