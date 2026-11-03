import 'package:flutter/material.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';
import 'package:intl/intl.dart';

/// Timeline, resolution notes and SLA panels shared by the mobile and desktop
/// ticket detail screens, so both show identical content for a ticket.

IconData ticketActivityIcon(TicketActivityAction action) => switch (action) {
  TicketActivityAction.created => Icons.add_circle_outline_rounded,
  TicketActivityAction.assigned => Icons.person_add_alt_rounded,
  TicketActivityAction.statusChanged => Icons.sync_alt_rounded,
  TicketActivityAction.escalated => Icons.arrow_upward_rounded,
  TicketActivityAction.commented => Icons.chat_bubble_outline_rounded,
  TicketActivityAction.reopened => Icons.replay_rounded,
  TicketActivityAction.closed => Icons.lock_outline_rounded,
};

Color ticketActivityColor(TicketActivityAction action) => switch (action) {
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

String _formatDuration(Duration d) {
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  final days = d.inHours ~/ 24;
  final hours = d.inHours % 24;
  return hours == 0 ? '${days}d' : '${days}d ${hours}h';
}

class TicketActivityTrail extends StatelessWidget {
  final List<TicketActivity> activity;

  const TicketActivityTrail({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) {
      return Text(
        'No activity yet.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      children: [
        for (var i = 0; i < activity.length; i++)
          _TimelineRow(
            isLast: i == activity.length - 1,
            icon: ticketActivityIcon(activity[i].action),
            color: ticketActivityColor(activity[i].action),
            title: _describeActivity(activity[i]),
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
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
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
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        DateFormat.MMMd().add_jm().format(timestamp),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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

/// The "Resolution notes" callout shown on a resolved/closed ticket.
class TicketResolutionNotesCard extends StatelessWidget {
  final String notes;

  const TicketResolutionNotesCard({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StatusColors.resolved.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: StatusColors.resolved.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.task_alt_rounded,
                size: 16,
                color: StatusColors.resolved,
              ),
              const SizedBox(width: 6),
              Text(
                'Resolution notes',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: StatusColors.resolved,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(notes, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// SLA status card. Uses the same SlaCalculator math as the Admin Dashboard,
/// so this ticket's numbers always agree with the aggregate ones.
class TicketSlaCard extends StatelessWidget {
  final Ticket ticket;
  final SlaPolicy policy;

  const TicketSlaCard({super.key, required this.ticket, required this.policy});

  @override
  Widget build(BuildContext context) {
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

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
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
              Icon(Icons.timer_outlined, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Text('SLA status', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              _SlaBadge(label: statusLabel, color: statusColor),
            ],
          ),
          const Divider(height: 28),
          _SlaRow(label: 'Priority', value: ticket.priority.label),
          _SlaRow(label: 'Target window', value: '$targetHours hours'),
          _SlaRow(
            label: resolvedAt != null ? 'Time to resolve' : 'Elapsed',
            value: _formatDuration(elapsed),
          ),
          if (resolvedAt == null)
            _SlaRow(
              label: overdue ? 'Overdue by' : 'Time remaining',
              value: _formatDuration(
                Duration(hours: (elapsedHours - targetHours).abs()),
              ),
            ),
        ],
      ),
    );
  }
}

class _SlaRow extends StatelessWidget {
  final String label;
  final String value;

  const _SlaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _SlaBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SlaBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}
