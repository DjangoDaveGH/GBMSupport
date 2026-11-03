import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/routing/safe_pop.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_attachments_section.dart';
import 'package:hyport/features/tickets/presentation/ticket_detail_shared.dart';
import 'package:hyport/features/tickets/presentation/requester_ticket_history_panel.dart';
import 'package:intl/intl.dart';

/// Phase 5 mockup screen 32 — the same ticket, activity, SLA and escalation
/// content as the mobile Ticket Detail, laid out as a two-column web page
/// (main content + info sidebar) with an "Actions" menu instead of a bottom
/// toolbar. Calls the exact same TicketRepository methods as the mobile
/// version; only the chrome around them differs.
class DesktopTicketDetailScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const DesktopTicketDetailScreen({super.key, required this.ticketId});

  @override
  ConsumerState<DesktopTicketDetailScreen> createState() =>
      _DesktopTicketDetailScreenState();
}

class _DesktopTicketDetailScreenState
    extends ConsumerState<DesktopTicketDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );
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
        if (ticket == null)
          return const Center(child: Text('Ticket not found.'));
        if (viewer == null) return const BrandedLoaderCenter();
        return _buildBody(context, ticket, viewer);
      },
    );
  }

  Widget _buildBody(BuildContext context, Ticket ticket, AppUser viewer) {
    final isAssignee = viewer.id == ticket.assignedTo;
    final canAssign =
        (viewer.role == UserRole.supportCoordinator ||
            viewer.role == UserRole.pfmManagement) &&
        ticket.status != TicketStatus.closed;
    final canEscalate =
        (viewer.role == UserRole.supportCoordinator &&
            ticket.status != TicketStatus.closed &&
            ticket.status != TicketStatus.resolved) ||
        ((viewer.role == UserRole.functionalLead ||
                viewer.role == UserRole.technicalLead) &&
            isAssignee &&
            ticket.status != TicketStatus.closed &&
            ticket.status != TicketStatus.resolved &&
            ticket.escalationLevel < 2);
    final canStartWork =
        isAssignee &&
        const {
          TicketStatus.assigned,
          TicketStatus.escalated,
          TicketStatus.reopened,
        }.contains(ticket.status);
    final canResolve =
        isAssignee &&
        const {
          TicketStatus.assigned,
          TicketStatus.inProgress,
          TicketStatus.escalated,
          TicketStatus.reopened,
        }.contains(ticket.status);

    // Same role/status rules as the mobile ticket detail's overflow menu, so
    // the desktop Actions menu offers exactly what mobile's Actions sheet does.
    final menuItems = <(String, IconData, VoidCallback)>[
      if (canAssign)
        (
          ticket.assignedTo == null ? 'Assign' : 'Reassign',
          Icons.person_add_alt_rounded,
          () => context.push('/tickets/${ticket.id}/assign'),
        ),
      if (canEscalate)
        (
          'Escalate',
          Icons.arrow_upward_rounded,
          () => _showEscalateDialog(context, ticket, viewer),
        ),
      if (viewer.role == UserRole.functionalLead ||
          viewer.role == UserRole.technicalLead) ...[
        if (canStartWork)
          (
            'Start Work',
            Icons.play_arrow_rounded,
            () => _changeStatus(ticket, viewer, TicketStatus.inProgress),
          ),
        if (canResolve)
          (
            'Resolve',
            Icons.check_circle_outline_rounded,
            () => _changeStatus(ticket, viewer, TicketStatus.resolved),
          ),
      ],
      if (viewer.role == UserRole.vendorSupport && canResolve)
        (
          'Resolve',
          Icons.check_circle_outline_rounded,
          () => _changeStatus(ticket, viewer, TicketStatus.resolved),
        ),
      if (viewer.role == UserRole.pfmManagement &&
          (ticket.status == TicketStatus.resolved ||
              ticket.status == TicketStatus.closed))
        (
          'Reopen Ticket',
          Icons.replay_rounded,
          () => _changeStatus(ticket, viewer, TicketStatus.reopened),
        ),
      if (viewer.role.hasBackOfficeAccess &&
          ticket.status == TicketStatus.resolved)
        (
          'Close Ticket',
          Icons.lock_outline_rounded,
          () => ref
              .read(ticketRepositoryProvider)
              .close(ticketId: ticket.id, actorId: viewer.id),
        ),
    ];

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => context.popOrGo('/tickets'),
                          child: const Text('← Tickets'),
                        ),
                        Flexible(
                          child: Text(
                            ' / #${ticket.ticketReference}',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Same action set as the mobile ticket detail: Chat, Assign,
                  // Escalate, then the Actions menu for the status changes. Wrap
                  // (not a single Row) so buttons drop to a new line instead of
                  // running off the right edge on narrower windows.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/tickets/${ticket.id}/chat'),
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Chat'),
                      ),
                      if (canAssign)
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/tickets/${ticket.id}/assign'),
                          icon: const Icon(
                            Icons.person_add_alt_rounded,
                            size: 18,
                          ),
                          label: Text(
                            ticket.assignedTo == null ? 'Assign' : 'Reassign',
                          ),
                        ),
                      if (canEscalate)
                        OutlinedButton.icon(
                          onPressed: () =>
                              _showEscalateDialog(context, ticket, viewer),
                          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                          label: const Text('Escalate'),
                        ),
                      if (menuItems.isNotEmpty)
                        OutlinedButton.icon(
                          key: _actionsButtonKey,
                          onPressed: () => _showActionsMenu(context, menuItems),
                          icon: const Icon(Icons.more_horiz_rounded, size: 18),
                          label: const Text('Actions'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _MainColumn(
                        ticket: ticket,
                        tabController: _tabController,
                        noteController: _noteController,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 1,
                      child: SingleChildScrollView(
                        child: _SidebarColumn(ticket: ticket),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 28,
          bottom: 28,
          child: FloatingActionButton(
            heroTag: 'desktop-ticket-chat-${ticket.id}',
            tooltip: 'Chat about this ticket',
            backgroundColor: AppTheme.navy,
            foregroundColor: Colors.white,
            onPressed: () => context.push('/tickets/${ticket.id}/chat'),
            child: const Icon(Icons.chat_bubble_outline_rounded),
          ),
        ),
      ],
    );
  }

  void _showActionsMenu(
    BuildContext context,
    List<(String, IconData, VoidCallback)> items,
  ) {
    final button =
        _actionsButtonKey.currentContext!.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<void>(
      context: context,
      position: position,
      items: items
          .map<PopupMenuEntry<void>>(
            (item) => PopupMenuItem<void>(
              onTap: item.$3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.$2, size: 18, color: AppTheme.accentBlue),
                  const SizedBox(width: 10),
                  Text(item.$1),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _changeStatus(
    Ticket ticket,
    AppUser viewer,
    TicketStatus status,
  ) {
    return ref
        .read(ticketRepositoryProvider)
        .changeStatus(ticketId: ticket.id, to: status, actorId: viewer.id);
  }

  void _showEscalateDialog(
    BuildContext context,
    Ticket ticket,
    AppUser viewer,
  ) {
    final noteController = TextEditingController();
    final targetLevel = ticket.escalationLevel < 1 ? 1 : 2;
    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (dialogContext, ref, _) {
          final usersAsync = ref.watch(assignableUsersProvider);
          return AlertDialog(
            title: Text(
              targetLevel == 1
                  ? 'Escalate to Applications Systems Unit'
                  : 'Escalate to Vendor/Specialist',
            ),
            content: usersAsync.when(
              loading: () =>
                  const SizedBox(height: 80, child: BrandedLoaderCenter()),
              error: (e, _) => const Text('Users unavailable'),
              data: (users) {
                final eligible = users.where((u) {
                  if (targetLevel == 1) {
                    // One Applications Systems Unit now — the functional/
                    // technical split no longer maps to distinct people, so
                    // level-1 escalation targets any active APPS member.
                    return u.role == UserRole.functionalLead ||
                        u.role == UserRole.technicalLead;
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
                        decoration: const InputDecoration(
                          labelText: 'Escalation note (optional)',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      ...eligible.map(
                        (u) => ListTile(
                          title: Text(u.name),
                          subtitle: Text(u.role.shortLabel),
                          onTap: () async {
                            await ref
                                .read(ticketRepositoryProvider)
                                .escalate(
                                  ticketId: ticket.id,
                                  toLevel: targetLevel,
                                  assigneeId: u.id,
                                  actorId: viewer.id,
                                  note: noteController.text.trim(),
                                );
                            if (dialogContext.mounted)
                              Navigator.of(dialogContext).pop();
                          },
                        ),
                      ),
                      if (eligible.isEmpty)
                        const Text(
                          'No eligible staff found for this category.',
                        ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MainColumn extends ConsumerWidget {
  final Ticket ticket;
  final TabController tabController;
  final TextEditingController noteController;

  const _MainColumn({
    required this.ticket,
    required this.tabController,
    required this.noteController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary keeps its natural height so the title, status and
          // description are readable at a glance; the tabs take the rest.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.title,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ticket.priority == TicketPriority.critical ||
                    ticket.priority == TicketPriority.high) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.flag_rounded,
                        size: 15,
                        color: StatusColors.critical,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${ticket.priority.label} Priority',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: StatusColors.critical),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TicketStatusChip(status: ticket.status),
                    TicketPriorityChip(priority: ticket.priority),
                    _PlainBadge(label: ticket.categoryLabel),
                    if (ticket.subCategory.isNotEmpty)
                      _PlainBadge(label: ticket.subCategory),
                    if (ticket.escalationLevel > 0)
                      _PlainBadge(
                        label: 'Escalation level ${ticket.escalationLevel}',
                        color: StatusColors.critical,
                      ),
                  ],
                ),
                if (ticket.description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ExpandableText(text: ticket.description),
                ],
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: TabBar(
              controller: tabController,
              isScrollable: true,
              labelColor: AppTheme.navy,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              indicatorColor: AppTheme.navy,
              tabs: const [
                Tab(text: 'Details'),
                Tab(text: 'Timeline'),
                Tab(text: 'SLA'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                _DetailsView(ticket: ticket),
                _TimelineView(ticketId: ticket.id),
                _SlaView(ticket: ticket),
              ],
            ),
          ),
          // This composer writes a plain TicketActivity comment — the same
          // feed rendered to the requester and the mobile chat screen, not a
          // private note and not a status change. Locked once resolved/closed,
          // mirroring TicketChatScreen's _chatClosed so this screen can't be
          // used to post into a conversation the requester was told had ended.
          if (ticket.status == TicketStatus.resolved ||
              ticket.status == TicketStatus.closed)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Text(
                'This ticket is ${ticket.status == TicketStatus.closed ? 'closed' : 'resolved'} — chat is now closed.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        hintText: 'Add chat message...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () async {
                      final viewer = ref
                          .read(currentAppUserProvider)
                          .valueOrNull;
                      if (viewer == null || noteController.text.trim().isEmpty)
                        return;
                      await ref
                          .read(ticketRepositoryProvider)
                          .addComment(
                            ticketId: ticket.id,
                            actorId: viewer.id,
                            note: noteController.text.trim(),
                          );
                      noteController.clear();
                    },
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows the first few lines of a long description with a toggle, so one long
/// description can't push the tabs below the fold.
class _ExpandableText extends StatefulWidget {
  final String text;

  const _ExpandableText({required this.text});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > 160;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: Theme.of(context).textTheme.bodyMedium,
          maxLines: _expanded || !isLong ? null : 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (isLong)
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
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
      error: (e, _) => Center(child: Text('Could not load activity: $e')),
      data: (activity) => ListView(
        padding: const EdgeInsets.all(20),
        children: [TicketActivityTrail(activity: activity)],
      ),
    );
  }
}

class _DetailsView extends StatelessWidget {
  final Ticket ticket;

  const _DetailsView({required this.ticket});

  @override
  Widget build(BuildContext context) {
    // A wrapping grid instead of one tall list, so the fields are visible
    // together on a wide screen.
    final fields = <Widget>[
      _InfoRow(label: 'Category', value: ticket.categoryLabel),
      if (ticket.subCategory.isNotEmpty)
        _InfoRow(label: 'Sub-category', value: ticket.subCategory),
      _InfoRow(label: 'Priority', value: ticket.priority.label),
      _InfoRow(label: 'Impact', value: ticket.impact.label),
      _InfoRow(label: 'Status', value: ticket.status.label),
      _InfoRow(
        label: 'Created',
        value: DateFormat.yMMMd().add_jm().format(ticket.createdAt),
      ),
      if (ticket.resolvedAt != null)
        _InfoRow(
          label: 'Resolved',
          value: DateFormat.yMMMd().add_jm().format(ticket.resolvedAt!),
        ),
      if (ticket.closedAt != null)
        _InfoRow(
          label: 'Closed',
          value: DateFormat.yMMMd().add_jm().format(ticket.closedAt!),
        ),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 32,
          children: fields
              .map((field) => SizedBox(width: 240, child: field))
              .toList(),
        ),
        if (ticket.attachmentUrls.isNotEmpty) ...[
          const SizedBox(height: 8),
          TicketAttachmentsSection(attachmentUrls: ticket.attachmentUrls),
        ],
        if (ticket.resolutionNotes != null &&
            ticket.resolutionNotes!.isNotEmpty) ...[
          const SizedBox(height: 18),
          TicketResolutionNotesCard(notes: ticket.resolutionNotes!),
        ],
      ],
    );
  }
}

class _SlaView extends ConsumerWidget {
  final Ticket ticket;

  const _SlaView({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policyAsync = ref.watch(slaPolicyProvider);
    return policyAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => const Center(child: Text('SLA information unavailable')),
      data: (policy) => ListView(
        padding: const EdgeInsets.all(20),
        children: [TicketSlaCard(ticket: ticket, policy: policy)],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
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
    final policy =
        ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();
    final due = ticket.createdAt.add(
      Duration(hours: policy.targetHoursFor(ticket.priority)),
    );
    final viewer = ref.watch(currentAppUserProvider).valueOrNull;

    return Column(
      children: [
        _SidebarCard(
          title: 'Ticket Information',
          child: Column(
            children: [
              _InfoRow(label: 'ID', value: ticket.ticketReference),
              _InfoRow(label: 'Status', value: ticket.status.label),
              _InfoRow(label: 'Priority', value: ticket.priority.label),
              _InfoRow(label: 'Category', value: ticket.categoryLabel),
              _InfoRow(
                label: 'Created',
                value: DateFormat.yMMMd().add_jm().format(ticket.createdAt),
              ),
              _InfoRow(
                label: 'Last Updated',
                value: DateFormat.yMMMd().add_jm().format(ticket.updatedAt),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Same visibility rule as the mobile Details tab: every support-side
        // role (including Vendor/Specialist) sees who raised the ticket.
        if (viewer?.role.isSupportSide ?? false) ...[
          _SidebarCard(
            title: 'Requested By',
            child: _AssigneeInfo(
              userId: ticket.createdBy,
              showInstitution: true,
            ),
          ),
          const SizedBox(height: 16),
        ],
        RequesterTicketHistoryPanel(ticket: ticket, compact: true),
        if (ticket.assignedTo != null)
          _SidebarCard(
            title: 'Assigned To',
            child: (viewer?.role.isSupportSide ?? false)
                ? _AssigneeInfo(userId: ticket.assignedTo!)
                // Requester can't read the assignee's users/{uid} doc — show
                // the denormalized name from the ticket.
                : Text(
                    ticket.assignedToName ?? 'A support agent',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        const SizedBox(height: 16),
        _SidebarCard(
          title: 'SLA Due',
          child: Row(
            children: [
              const Icon(
                Icons.event_outlined,
                size: 16,
                color: AppTheme.accentBlue,
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat.yMMMd().add_jm().format(due),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
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

  /// When true, show the user's specific assembly/MDA (resolved from
  /// institutionId) beside their role instead of just the role — used for the
  /// "Requested By" card so back-office staff see which institution the
  /// end user belongs to, not merely "MDA/MMDA User".
  final bool showInstitution;

  const _AssigneeInfo({required this.userId, this.showInstitution = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userByIdProvider(userId));
    return userAsync.when(
      loading: () => const SizedBox(height: 40, child: BrandedLoaderCenter()),
      error: (e, _) => const Text('Unavailable'),
      data: (user) {
        if (user == null) return const Text('Not found.');
        var subtitle = user.role.shortLabel;
        if (showInstitution) {
          final institutions =
              ref.watch(institutionListProvider).valueOrNull ?? const [];
          var institutionLabel = user.institutionType.wireValue;
          for (final i in institutions) {
            if (i.id == user.institutionId) {
              institutionLabel = i.name;
              break;
            }
          }
          subtitle = '${user.role.shortLabel} · $institutionLabel';
        }
        return Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
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
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c),
      ),
    );
  }
}
