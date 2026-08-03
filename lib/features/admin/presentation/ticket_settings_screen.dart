import 'package:flutter/material.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;

/// Read-only — categories/priorities are seed data, not user-editable in
/// the MVP (same scope note as NewTicketScreen's sub-category map). This
/// screen exists so admins can see the current configuration even though
/// they can't change it yet.
class TicketSettingsScreen extends StatelessWidget {
  const TicketSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ticket Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Categories and priorities are fixed for this build, not editable here yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Text('Categories', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          ...TicketCategory.values.map((c) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(categoryIcon(c), size: 18, color: AppTheme.accentBlue),
                    const SizedBox(width: 10),
                    Text(c.label, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              )),
          const SizedBox(height: AppSpacing.lg),
          Text('Priorities', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TicketPriority.values
                .map((p) => Chip(label: Text(p.label)))
                .toList(),
          ),
        ],
      ),
    );
  }
}
