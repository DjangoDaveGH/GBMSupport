import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/models/support_system.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';

/// Shows requester history using the viewer's normal ticket scope. Leads and
/// vendors therefore see only tickets they are allowed to access, while
/// management/coordinators see the broader history for their tenant.
class RequesterTicketHistoryPanel extends ConsumerWidget {
  final Ticket ticket;
  final bool compact;

  const RequesterTicketHistoryPanel({
    super.key,
    required this.ticket,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(currentAppUserProvider).valueOrNull;
    if (viewer == null || !viewer.role.isSupportSide) {
      return const SizedBox.shrink();
    }
    // Guest submissions have no stable user id. They remain visible on the
    // ticket itself; do not accidentally merge unrelated guest requesters.
    if (ticket.createdBy == 'guest' || ticket.createdBy.isEmpty) {
      return const SizedBox.shrink();
    }
    final isAssigned = ticket.assignedTo == viewer.id;
    final isManagement =
        viewer.role == UserRole.pfmManagement ||
        viewer.role == UserRole.supportCoordinator;
    if (!isAssigned && !isManagement) return const SizedBox.shrink();

    final historyAsync = ref.watch(
      ticketAnalyticsProvider((
        viewer,
        TicketFilter(createdBy: ticket.createdBy),
      )),
    );

    return historyAsync.when(
      loading: () => const SizedBox(height: 64, child: BrandedLoaderCenter()),
      error: (error, _) => _Panel(
        compact: compact,
        child: Text('Could not load requester history: $error'),
      ),
      data: (tickets) {
        final previous = tickets
            .where((item) => item.id != ticket.id)
            .take(6)
            .toList();
        return _Panel(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppTheme.accentBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Other tickets from this requester',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '${tickets.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (previous.isEmpty)
                Text(
                  'No other visible tickets from this requester.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                for (final item in previous) _HistoryRow(ticket: item),
              if (tickets.length > 7) ...[
                const SizedBox(height: 6),
                Text(
                  'Showing the 6 most recent previous tickets.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final bool compact;

  const _Panel({required this.child, required this.compact});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: EdgeInsets.only(bottom: compact ? 12 : 16),
    padding: EdgeInsets.all(compact ? 12 : 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
}

class _HistoryRow extends StatelessWidget {
  final Ticket ticket;

  const _HistoryRow({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => context.push('/tickets/${ticket.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${ticket.ticketReference} · ${ticket.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${supportSystemLabel(ticket.system)} · ${ticket.status.label} · ${ticket.assignedToName ?? 'Unassigned'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
