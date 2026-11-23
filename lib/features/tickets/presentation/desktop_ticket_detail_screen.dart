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
import 'package:hyport/features/tickets/presentation/admin_status_actions.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_attachments_section.dart';
import 'package:hyport/features/tickets/presentation/ticket_detail_shared.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart'
    show categoryIcon;
import 'package:hyport/features/tickets/presentation/requester_ticket_history_panel.dart';
import 'package:intl/intl.dart';

/// Phase 5 mockup screen 32 — the PC web view of the ticket detail. It shows
/// the same content as the mobile Ticket Detail, in the same order, laid out
/// as a two-column page: the ticket and its tabs on the left, SLA and history
/// on the right. Calls the exact same TicketRepository methods as mobile;
/// only the chrome around them differs.
class DesktopTicketDetailScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const DesktopTicketDetailScreen({super.key, required this.ticketId});

  @override
  ConsumerState<DesktopTicketDetailScreen> createState() =>
      _DesktopTicketDetailScreenState();
}

class _DesktopTicketDetailScreenState
    extends ConsumerState<DesktopTicketDetailScreen> {
  final _noteController = TextEditingController();
  final _actionsButtonKey = GlobalKey();

  @override
  void dispose() {
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
        if (ticket == null) {
          return const Center(child: Text('Ticket not found.'));
        }
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
      // PFM Management gets Resolve/Close/Reopen as their own buttons
      // (admin_status_actions.dart), so it's left out of this menu entry.
      if (viewer.role.hasBackOfficeAccess &&
          viewer.role != UserRole.pfmManagement &&
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
              const SizedBox(height: 8),
              // Same action set as the mobile action row: Chat, Assign,
              // Escalate, then the Actions menu for the status changes. It
              // sits on its own right-aligned row so the buttons always get
              // the full width.
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
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
                    ...adminStatusButtons(
                      context: context,
                      ref: ref,
                      ticket: ticket,
                      viewer: viewer,
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
                        viewer: viewer,
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
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
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

/// Left column: the ticket summary (title, chips, the three facts people look
/// for first), then every ticket section on one scrollable page, then the chat
/// composer. Nothing sits behind a tab or a "Show more" toggle.
class _MainColumn extends ConsumerWidget {
  final Ticket ticket;
  final AppUser viewer;
  final TextEditingController noteController;

  const _MainColumn({
    required this.ticket,
    required this.viewer,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: _SummaryPanel(ticket: ticket, viewer: viewer),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: _TicketSections(ticket: ticket, viewer: viewer),
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
                      if (viewer == null ||
                          noteController.text.trim().isEmpty) {
                        return;
                      }
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

/// Summary at the top of the left column — the same facts as the mobile
/// header card: title, reference, chips, then Assigned / Created / Updated.
class _SummaryPanel extends StatelessWidget {
  final Ticket ticket;
  final AppUser viewer;

  const _SummaryPanel({required this.ticket, required this.viewer});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                categoryIcon(ticket.category),
                color: AppTheme.accentBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '#${ticket.ticketReference}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TicketPriorityChip(priority: ticket.priority),
            TicketBadge(label: ticket.categoryLabel),
            if (ticket.subCategory.isNotEmpty)
              TicketBadge(label: ticket.subCategory),
            if (ticket.escalationLevel > 0)
              TicketBadge(
                label: 'Escalation level ${ticket.escalationLevel}',
                color: StatusColors.critical,
              ),
          ],
        ),
        const Divider(height: 26),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
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
            Expanded(
              child: TicketFactCell(
                label: 'Created',
                value: DateFormat.yMMMd().add_jm().format(ticket.createdAt),
              ),
            ),
            Expanded(
              child: TicketFactCell(
                label: 'Updated',
                value: DateFormat.yMMMd().add_jm().format(ticket.updatedAt),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Every section of the ticket on one scrollable page: the facts, the full
/// description (not clamped), attachments, resolution notes, the requester
/// (support side only), SLA and the activity timeline.
class _TicketSections extends ConsumerWidget {
  final Ticket ticket;
  final AppUser viewer;

  const _TicketSections({required this.ticket, required this.viewer});

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
          value: DateFormat.yMMMd().add_jm().format(ticket.resolvedAt!),
        ),
      if (ticket.closedAt != null)
        TicketFactCell(
          label: 'Closed',
          value: DateFormat.yMMMd().add_jm().format(ticket.closedAt!),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _SectionTitle('Ticket information'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 16,
          children: facts
              .map((fact) => SizedBox(width: 150, child: fact))
              .toList(),
        ),
        const SizedBox(height: 22),
        const _SectionTitle('Description'),
        const SizedBox(height: 8),
        Text(ticket.description, style: Theme.of(context).textTheme.bodyMedium),
        if (ticket.attachmentUrls.isNotEmpty) ...[
          const SizedBox(height: 18),
          TicketAttachmentsSection(attachmentUrls: ticket.attachmentUrls),
        ],
        if (ticket.resolutionNotes != null &&
            ticket.resolutionNotes!.isNotEmpty) ...[
          const SizedBox(height: 18),
          TicketResolutionNotesCard(notes: ticket.resolutionNotes!),
        ],
        if (viewer.role.isSupportSide) ...[
          const SizedBox(height: 22),
          const _SectionTitle('Requested By'),
          const SizedBox(height: 12),
          _AssigneeInfo(userId: ticket.createdBy, showInstitution: true),
        ],
        const SizedBox(height: 22),
        const _SectionTitle('SLA'),
        const SizedBox(height: 12),
        ref
            .watch(slaPolicyProvider)
            .when(
              loading: () =>
                  const SizedBox(height: 80, child: BrandedLoaderCenter()),
              error: (e, _) => const Text('SLA information unavailable'),
              data: (policy) => TicketSlaCard(ticket: ticket, policy: policy),
            ),
        const SizedBox(height: 10),
        const _SectionTitle('Timeline'),
        const SizedBox(height: 12),
        ref
            .watch(ticketActivityProvider(ticket.id))
            .when(
              loading: () =>
                  const SizedBox(height: 80, child: BrandedLoaderCenter()),
              error: (e, _) => Text('Could not load activity: $e'),
              data: (activity) => TicketActivityTrail(activity: activity),
            ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

/// Right column: the SLA due date and the requester's ticket history. The
/// facts and people live in the summary and the Details tab, so they are not
/// repeated here.
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

    return Column(
      children: [
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
        const SizedBox(height: 16),
        RequesterTicketHistoryPanel(ticket: ticket, compact: true),
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

/// Avatar, name, and role/institution for a person on the ticket. Used for
/// the Requested By card; [showInstitution] shows the requester's specific
/// MDA/MMDA name instead of just the broad type.
class _AssigneeInfo extends ConsumerWidget {
  final String userId;
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
