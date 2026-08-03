import 'package:flutter/material.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// Soft tinted pill badge — a dot + label in a tint of the status color,
/// rather than a solid block. Reads calmer at a glance across a dense list
/// of tickets, while still being scannable by color.
class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

class TicketStatusChip extends StatelessWidget {
  final TicketStatus status;

  const TicketStatusChip({super.key, required this.status});

  Color get _color => switch (status) {
        TicketStatus.open => StatusColors.open,
        TicketStatus.assigned => StatusColors.assigned,
        TicketStatus.inProgress => StatusColors.inProgress,
        TicketStatus.escalated => StatusColors.escalated,
        TicketStatus.resolved => StatusColors.resolved,
        TicketStatus.reopened => StatusColors.reopened,
        TicketStatus.closed => StatusColors.closed,
      };

  @override
  Widget build(BuildContext context) => _Badge(label: status.label, color: _color);
}

class TicketPriorityChip extends StatelessWidget {
  final TicketPriority priority;

  const TicketPriorityChip({super.key, required this.priority});

  Color get _color => switch (priority) {
        TicketPriority.critical => StatusColors.critical,
        TicketPriority.high => StatusColors.high,
        TicketPriority.medium => StatusColors.medium,
        TicketPriority.low => StatusColors.low,
      };

  @override
  Widget build(BuildContext context) => _Badge(label: priority.label, color: _color);
}
