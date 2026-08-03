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
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';

/// Dedicated full-screen assign flow (Phase 4 mockup screen 21) — replaces
/// the dialog previously used from Ticket Detail with the same
/// search-then-pick-then-note-then-confirm shape as the mockup, still
/// calling the same TicketRepository.assignTicket underneath.
class AssignTicketScreen extends ConsumerStatefulWidget {
  final String ticketId;

  /// When true, renders just the content with no Scaffold/AppBar of its
  /// own — for embedding inside DesktopShell. See NotificationsScreen's
  /// doc comment for why.
  final bool embedded;

  const AssignTicketScreen({super.key, required this.ticketId, this.embedded = false});

  @override
  ConsumerState<AssignTicketScreen> createState() => _AssignTicketScreenState();
}

class _AssignTicketScreenState extends ConsumerState<AssignTicketScreen> {
  final _searchController = TextEditingController();
  final _noteController = TextEditingController();
  String _search = '';
  String? _selectedUserId;
  bool _submitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    final viewer = ref.read(currentAppUserProvider).valueOrNull;
    if (viewer == null || _selectedUserId == null) return;
    setState(() => _submitting = true);
    try {
      await ref.read(ticketRepositoryProvider).assignTicket(
            ticketId: widget.ticketId,
            assigneeId: _selectedUserId!,
            actorId: viewer.id,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket assigned.')));
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketDetailProvider(widget.ticketId));
    final usersAsync = ref.watch(assignableUsersProvider);

    final body = ticketAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Center(child: Text('Could not load ticket: $e')),
        data: (ticket) {
          if (ticket == null) return const Center(child: Text('Ticket not found.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TicketSummaryCard(ticket: ticket),
              const SizedBox(height: AppSpacing.xl),
              Text('Assign To', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search officer…',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              usersAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(24), child: BrandedLoaderCenter()),
                error: (e, _) => Text('Could not load officers: $e'),
                data: (users) {
                  // Vendor/Specialist is reachable only via "Escalate to
                  // Vendor/Specialist" (sets escalationLevel to 2 in the
                  // same write as assignedTo). Plain Assign must not offer
                  // them: TicketRepository.assignTicket() sets assignedTo
                  // alone, and both firestore.rules' vendor read rule and
                  // TicketRepository.scopedQuery require escalationLevel
                  // == 2 for a vendor to see a ticket at all — a plain
                  // assign to Vendor would silently vanish from their queue.
                  final assignable = users.where((u) => u.role != UserRole.vendorSupport);
                  final filtered = _search.isEmpty
                      ? assignable.toList()
                      : assignable.where((u) => u.name.toLowerCase().contains(_search)).toList();
                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No matching officers.'),
                    );
                  }
                  return Column(children: filtered.map(_officerRow).toList());
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Add Note (optional)', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(hintText: 'Type note...'),
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: (_selectedUserId == null || _submitting) ? null : _assign,
                child: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('ASSIGN TICKET'),
              ),
            ],
          );
        },
      );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Assign Ticket')), body: body);
  }

  Widget _officerRow(AppUser u) {
    final selected = u.id == _selectedUserId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accentBlue.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: selected ? AppTheme.accentBlue : Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => setState(() => _selectedUserId = u.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
                child: Text(
                  u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.name, style: Theme.of(context).textTheme.titleSmall),
                    Text(u.role.label, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? AppTheme.accentBlue : Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketSummaryCard extends StatelessWidget {
  final Ticket ticket;

  const _TicketSummaryCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('#${ticket.ticketReference}', style: Theme.of(context).textTheme.bodySmall)),
              TicketPriorityChip(priority: ticket.priority),
            ],
          ),
          const SizedBox(height: 6),
          Text(ticket.title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
