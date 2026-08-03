import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/dashboard/data/report_providers.dart';
import 'package:intl/intl.dart';

const _reportTypes = [
  ('summary', 'Tickets Summary Report', 'Overview of all tickets', Icons.summarize_rounded),
  ('sla', 'SLA Compliance Report', 'SLA performance overview', Icons.verified_rounded),
  ('officer_performance', 'Officer Performance Report', 'Performance by officer', Icons.badge_rounded),
  ('category_breakdown', 'Category Breakdown', 'Tickets by category', Icons.pie_chart_rounded),
  ('monthly_trend', 'Monthly Trend Report', 'Ticket trend analysis', Icons.trending_up_rounded),
];

/// Phase 4 mockup screen 24. Reports are computed live from real ticket
/// data (see ReportDetailScreen) rather than exported/stored PDF files —
/// there's no Storage yet to persist those. "Recent Reports" is a genuine
/// log of report types this admin looked at, not fabricated file history.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final recentAsync = appUser == null ? null : ref.watch(recentReportViewsProvider(appUser.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Popular Reports', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          ..._reportTypes.map((r) {
            final (type, label, subtitle, icon) = r;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => context.push('/reports/$type', extra: label),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.accentBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(icon, size: 19, color: AppTheme.accentBlue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: Theme.of(context).textTheme.titleSmall),
                              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: AppSpacing.xl),
          Text('Recent Reports', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          if (recentAsync == null)
            const SizedBox.shrink()
          else
            recentAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Could not load recent reports: $e'),
              data: (views) {
                if (views.isEmpty) {
                  return Text(
                    'Reports you view will show up here.',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                }
                return Column(
                  children: views.map((v) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.description_outlined, size: 18, color: AppTheme.gold),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.reportLabel, style: Theme.of(context).textTheme.titleSmall),
                                Text(
                                  DateFormat.yMMMd().add_jm().format(v.viewedAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}
