import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';

/// Status changes PFM Management (the admin) can make on any ticket, shown
/// as their own buttons in the mobile and desktop ticket-detail action rows.
/// firestore.rules' pfm_management branch allows exactly these transitions.
enum AdminStatusAction {
  resolve('Resolve', Icons.check_circle_outline_rounded),
  close('Close Ticket', Icons.lock_outline_rounded),
  reopen('Reopen', Icons.replay_rounded);

  final String label;
  final IconData icon;
  const AdminStatusAction(this.label, this.icon);
}

const _resolvable = {
  TicketStatus.open,
  TicketStatus.assigned,
  TicketStatus.inProgress,
  TicketStatus.escalated,
  TicketStatus.reopened,
};

List<AdminStatusAction> adminStatusActionsFor(AppUser viewer, Ticket ticket) {
  if (viewer.role != UserRole.pfmManagement) return const [];
  final s = ticket.status;
  return [
    if (_resolvable.contains(s)) AdminStatusAction.resolve,
    if (s != TicketStatus.closed) AdminStatusAction.close,
    if (s == TicketStatus.resolved || s == TicketStatus.closed)
      AdminStatusAction.reopen,
  ];
}

/// Asks for confirmation (and, for Resolve, an optional resolution note),
/// then applies the change.
Future<void> runAdminStatusAction({
  required BuildContext context,
  required WidgetRef ref,
  required Ticket ticket,
  required AppUser viewer,
  required AdminStatusAction action,
}) async {
  final noteController = TextEditingController();
  final (title, body) = switch (action) {
    AdminStatusAction.resolve => (
      'Resolve ${ticket.ticketReference}?',
      'The requester will be asked to confirm the fix.',
    ),
    AdminStatusAction.close => (
      'Close ${ticket.ticketReference}?',
      ticket.status == TicketStatus.resolved
          ? 'The ticket will be marked finished.'
          : 'This ticket has not been resolved yet. Closing it marks it '
                'finished without a resolution.',
    ),
    AdminStatusAction.reopen => (
      'Reopen ${ticket.ticketReference}?',
      'It goes back into the queue as Reopened'
          '${ticket.assignedTo != null ? ' for the same officer' : ''}.',
    ),
  };

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          if (action == AdminStatusAction.resolve) ...[
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Resolution note (optional)',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(action.label),
        ),
      ],
    ),
  );
  final note = noteController.text.trim();
  noteController.dispose();
  if (confirmed != true) return;

  final repo = ref.read(ticketRepositoryProvider);
  try {
    switch (action) {
      case AdminStatusAction.resolve:
        await repo.changeStatus(
          ticketId: ticket.id,
          to: TicketStatus.resolved,
          actorId: viewer.id,
          note: note.isEmpty ? null : note,
        );
      case AdminStatusAction.close:
        await repo.close(ticketId: ticket.id, actorId: viewer.id);
      case AdminStatusAction.reopen:
        await repo.changeStatus(
          ticketId: ticket.id,
          to: TicketStatus.reopened,
          actorId: viewer.id,
        );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not ${action.label.toLowerCase()}: $e')),
      );
    }
  }
}

/// The admin buttons for [ticket], ready to drop into an action-row Wrap.
List<Widget> adminStatusButtons({
  required BuildContext context,
  required WidgetRef ref,
  required Ticket ticket,
  required AppUser viewer,
}) => [
  for (final action in adminStatusActionsFor(viewer, ticket))
    OutlinedButton.icon(
      onPressed: () => runAdminStatusAction(
        context: context,
        ref: ref,
        ticket: ticket,
        viewer: viewer,
        action: action,
      ),
      icon: Icon(action.icon, size: 18),
      label: Text(action.label),
    ),
];
