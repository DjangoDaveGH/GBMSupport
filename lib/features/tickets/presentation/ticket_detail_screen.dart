import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/routing/safe_pop.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_attachments_section.dart';
import 'package:hyport/features/tickets/presentation/ticket_detail_shared.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart'
    show categoryIcon;
import 'package:hyport/features/tickets/presentation/requester_ticket_history_panel.dart';
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
        leading: IconButton(
          tooltip: 'Back to tickets',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/tickets'),
        ),
        title: ticketAsync.valueOrNull != null
            ? Text('Ticket #${ticketAsync.valueOrNull!.ticketReference}')
            : const Text('Ticket Details'),
        actions: [
          if (ticketAsync.valueOrNull != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: TicketStatusChip(
                  status: ticketAsync.valueOrNull!.status,
                ),
              ),
            ),
          ],
        ],
      ),
      body: ticketAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Center(child: Text('Could not load ticket: $e')),
        data: (ticket) {
          if (ticket == null) {
            return const Center(child: Text('Ticket not found.'));
          }
          if (viewer == null) return const BrandedLoaderCenter();
          return _TicketDetailBody(ticket: ticket, viewer: viewer);
        },
      ),
      // Chat is also in the action row; the FAB keeps it one tap away while
      // the user scrolls the Details or Timeline tab.
      floatingActionButton: ticketAsync.valueOrNull == null
          ? null
          : FloatingActionButton(
              heroTag: 'ticket-chat-$ticketId',
              tooltip: 'Chat about this ticket',
              backgroundColor: AppTheme.navy,
              foregroundColor: Colors.white,
              onPressed: () => context.push('/tickets/$ticketId/chat'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
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

/// Compact header: title, reference, chips and the three facts people look
/// for first. Everything else lives in the tabs, so the screen shows the
/// important details without scrolling.
class _SummaryCard extends StatelessWidget {
  final Ticket ticket;
  final AppUser viewer;

  const _SummaryCard({required this.ticket, required this.viewer});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  categoryIcon(ticket.category),
                  color: AppTheme.accentBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${ticket.ticketReference}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TicketPriorityChip(priority: ticket.priority),
              TicketBadge(label: ticket.categoryLabel),
              if (ticket.subCategory.isNotEmpty)
                TicketBadge(label: ticket.subCategory),
              if (ticket.escalationLevel > 0)
                TicketBadge(
                  label: 'Escalation ${ticket.escalationLevel}',
                  color: StatusColors.critical,
                ),
            ],
          ),
          const Divider(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FactTile(
                  child: ticket.assignedTo != null
                      ? TicketAssignedCell(
                          userId: ticket.assignedTo!,
                          fallbackName: ticket.assignedToName,
                          attemptRead: viewer.role.isSupportSide,
                        )
                      : const TicketFactCell(
                          label: 'Assigned To',
                          value: 'Unassigned',
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FactTile(
                  child: TicketFactCell(
                    label: 'Created',
                    value: DateFormat.MMMd().add_jm().format(ticket.createdAt),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FactTile(
                  child: TicketFactCell(
                    label: 'Last updated',
                    value: DateFormat.MMMd().add_jm().format(ticket.updatedAt),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FactTile(
                  child: TicketFactCell(
                    label: 'Status',
                    value: ticket.status.label,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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

class _TicketDetailBodyState extends ConsumerState<_TicketDetailBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  Ticket get ticket => widget.ticket;
  AppUser get viewer => widget.viewer;

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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _SummaryCard(ticket: ticket, viewer: viewer),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: _buildActions(context, ref),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
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
            controller: _tabController,
            children: [
              _DetailsTab(ticket: ticket, viewer: viewer),
              _TimelineTab(ticketId: ticket.id),
              _SlaTab(ticket: ticket),
            ],
          ),
        ),
      ],
    );
  }

  bool get _canAssign =>
      (viewer.role == UserRole.supportCoordinator ||
          viewer.role == UserRole.pfmManagement) &&
      ticket.status != TicketStatus.closed;

  bool get _canEscalate =>
      (viewer.role == UserRole.supportCoordinator &&
          ticket.status != TicketStatus.closed &&
          ticket.status != TicketStatus.resolved) ||
      ((viewer.role == UserRole.functionalLead ||
              viewer.role == UserRole.technicalLead) &&
          _isAssignee &&
          ticket.status != TicketStatus.closed &&
          ticket.status != TicketStatus.resolved &&
          ticket.escalationLevel < 2);

  bool get _canStartWork =>
      _isAssignee &&
      const {
        TicketStatus.assigned,
        TicketStatus.escalated,
        TicketStatus.reopened,
      }.contains(ticket.status);

  bool get _canResolve =>
      _isAssignee &&
      const {
        TicketStatus.assigned,
        TicketStatus.inProgress,
        TicketStatus.escalated,
        TicketStatus.reopened,
      }.contains(ticket.status);

  /// Single-line, 40px buttons so the whole action row takes one line of
  /// screen height instead of a card with its own heading.
  static final ButtonStyle _compactActionStyle = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    visualDensity: VisualDensity.compact,
  );

  Widget _buildActions(BuildContext context, WidgetRef ref) {
    if (viewer.role.isSupportSide) return _buildAdminToolbar(context, ref);
    return _buildRequesterActions(context, ref);
  }

  /// Chat, Assign, Escalate, then the Actions menu for the status changes.
  /// "Actions" holds whatever's left of the role-gated action set (Start
  /// work/Resolve/Re-escalate/Close) — none of that business logic changed,
  /// only how it's surfaced.
  Widget _buildAdminToolbar(BuildContext context, WidgetRef ref) {
    final overflow = <(String, IconData, VoidCallback)>[];

    if (_canAssign) {
      overflow.add((
        ticket.assignedTo == null ? 'Assign' : 'Reassign',
        Icons.person_add_alt_rounded,
        () => context.push('/tickets/${ticket.id}/assign'),
      ));
    }
    if (_canEscalate) {
      overflow.add((
        'Escalate',
        Icons.arrow_upward_rounded,
        () => _showEscalateDialog(context, ref),
      ));
    }

    if ((viewer.role == UserRole.functionalLead ||
            viewer.role == UserRole.technicalLead) &&
        _canStartWork) {
      overflow.add((
        'Start Work',
        Icons.play_arrow_rounded,
        () {
          _changeStatus(ref, TicketStatus.inProgress);
        },
      ));
    }
    if ((viewer.role == UserRole.functionalLead ||
            viewer.role == UserRole.technicalLead) &&
        _canResolve) {
      overflow.add((
        'Resolve',
        Icons.check_circle_outline_rounded,
        () {
          _changeStatus(ref, TicketStatus.resolved);
        },
      ));
    }
    if (viewer.role == UserRole.vendorSupport && _canResolve) {
      overflow.add((
        'Resolve',
        Icons.check_circle_outline_rounded,
        () {
          _changeStatus(ref, TicketStatus.resolved);
        },
      ));
    }
    if (viewer.role == UserRole.pfmManagement &&
        (ticket.status == TicketStatus.resolved ||
            ticket.status == TicketStatus.closed)) {
      overflow.add((
        'Reopen Ticket',
        Icons.replay_rounded,
        () => _changeStatus(ref, TicketStatus.reopened),
      ));
    }
    if (viewer.role.hasBackOfficeAccess &&
        ticket.status == TicketStatus.resolved) {
      overflow.add((
        'Close Ticket',
        Icons.lock_outline_rounded,
        () => ref
            .read(ticketRepositoryProvider)
            .close(ticketId: ticket.id, actorId: viewer.id),
      ));
    }

    return OutlinedButtonTheme(
      data: OutlinedButtonThemeData(style: _compactActionStyle),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.push('/tickets/${ticket.id}/chat'),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Chat'),
          ),
          if (_canAssign)
            OutlinedButton.icon(
              onPressed: () => context.push('/tickets/${ticket.id}/assign'),
              icon: const Icon(Icons.person_add_alt_rounded, size: 18),
              label: Text(ticket.assignedTo == null ? 'Assign' : 'Reassign'),
            ),
          if (_canEscalate)
            OutlinedButton.icon(
              onPressed: () => _showEscalateDialog(context, ref),
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              label: const Text('Escalate'),
            ),
          if (overflow.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _showMoreSheet(context, overflow),
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              label: const Text('Actions'),
            ),
        ],
      ),
    );
  }

  void _showMoreSheet(
    BuildContext context,
    List<(String, IconData, VoidCallback)> items,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items
              .map(
                (item) => ListTile(
                  leading: Icon(item.$2, color: AppTheme.accentBlue),
                  title: Text(item.$1),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    item.$3();
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildRequesterActions(BuildContext context, WidgetRef ref) {
    return OutlinedButtonTheme(
      data: OutlinedButtonThemeData(style: _compactActionStyle),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.push('/tickets/${ticket.id}/chat'),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Chat'),
          ),
        ],
      ),
    );
  }

  void _showEscalateDialog(BuildContext context, WidgetRef ref) {
    final noteController = TextEditingController();
    final targetLevel = ticket.escalationLevel < 1 ? 1 : 2;
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
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
                            if (context.mounted) Navigator.of(context).pop();
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
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeStatus(WidgetRef ref, TicketStatus status) {
    return ref
        .read(ticketRepositoryProvider)
        .changeStatus(ticketId: ticket.id, to: status, actorId: viewer.id);
  }
}

/// A bordered tile around one fact, so each fact reads as its own block.
class _FactTile extends StatelessWidget {
  final Widget child;

  const _FactTile({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
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
        children: [TicketActivityTrail(activity: activity)],
      ),
    );
  }
}

/// Details tab: the facts not already in the header, then the description
/// and attachments. Assignee and status changes live in the header and the
/// action row, so they are not repeated here.
class _DetailsTab extends ConsumerWidget {
  final Ticket ticket;
  final AppUser viewer;

  const _DetailsTab({required this.ticket, required this.viewer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = <Widget>[
      if (ticket.subCategory.isNotEmpty)
        TicketFactCell(label: 'Sub-category', value: ticket.subCategory),
      TicketFactCell(label: 'Impact', value: ticket.impact.label),
      TicketFactCell(label: 'Status', value: ticket.status.label),
      if (ticket.resolvedAt != null)
        TicketFactCell(
          label: 'Resolved',
          value: DateFormat.MMMd().add_jm().format(ticket.resolvedAt!),
        ),
      if (ticket.closedAt != null)
        TicketFactCell(
          label: 'Closed',
          value: DateFormat.MMMd().add_jm().format(ticket.closedAt!),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ticket information',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: facts
                    .map(
                      (fact) =>
                          SizedBox(width: 160, child: _FactTile(child: fact)),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Description',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              // Full text, not clamped: the description is the first thing
              // people read, so nothing in it is hidden behind "Show more".
              Text(
                ticket.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (ticket.attachmentUrls.isNotEmpty) ...[
                const SizedBox(height: 14),
                TicketAttachmentsSection(attachmentUrls: ticket.attachmentUrls),
              ],
              if (ticket.resolutionNotes != null &&
                  ticket.resolutionNotes!.isNotEmpty) ...[
                const SizedBox(height: 14),
                TicketResolutionNotesCard(notes: ticket.resolutionNotes!),
              ],
            ],
          ),
        ),
        if (viewer.role.isSupportSide)
          _RequestedByCard(userId: ticket.createdBy),
        RequesterTicketHistoryPanel(ticket: ticket),
      ],
    );
  }
}

/// SLA tab (mockup screen 15's 4th tab). The card is shared with the desktop
/// ticket detail so both screens show the same SLA numbers.
class _SlaTab extends ConsumerWidget {
  final Ticket ticket;

  const _SlaTab({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policyAsync = ref.watch(slaPolicyProvider);
    return policyAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => const Center(child: Text('SLA information unavailable')),
      data: (policy) => ListView(
        padding: const EdgeInsets.all(16),
        children: [TicketSlaCard(ticket: ticket, policy: policy)],
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
        error: (e, _) => const Text('Requester unavailable'),
        data: (user) {
          if (user == null) return const Text('Requester not found.');
          // Resolve the requester's specific assembly/MDA name from their
          // institutionId; fall back to the broad MDA/MMDA type while the
          // institution list is still loading or if the id has no match.
          final institutions =
              ref.watch(institutionListProvider).valueOrNull ?? const [];
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
                  style: const TextStyle(
                    color: AppTheme.accentBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Requested By',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      user.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${user.role.shortLabel} · $institutionLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
