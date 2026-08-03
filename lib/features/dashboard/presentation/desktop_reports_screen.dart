import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/theme/app_theme.dart';

const _reportTypes = [
  ('summary', 'Tickets Summary', 'Overview of all tickets', Icons.summarize_rounded),
  ('sla', 'SLA Compliance', 'SLA performance overview', Icons.verified_rounded),
  ('officer_performance', 'Officer Performance', 'Performance by officer', Icons.badge_rounded),
  ('category_breakdown', 'Category Breakdown', 'Tickets by category', Icons.pie_chart_rounded),
  ('monthly_trend', 'Monthly Trend', 'Ticket trend analysis', Icons.trending_up_rounded),
];

/// Phase 5 mockup screen 38. Every "Generate" button pushes to the same
/// live-computed `/reports/:type` route the mobile Reports screen uses —
/// no separate desktop report-rendering logic to keep in sync.
class DesktopReportsScreen extends StatefulWidget {
  const DesktopReportsScreen({super.key});

  @override
  State<DesktopReportsScreen> createState() => _DesktopReportsScreenState();
}

class _DesktopReportsScreenState extends State<DesktopReportsScreen> {
  String _selected = 'all';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  _NavTile(label: 'All Reports', selected: _selected == 'all', onTap: () => setState(() => _selected = 'all')),
                  for (final r in _reportTypes)
                    _NavTile(label: r.$2, selected: _selected == r.$1, onTap: () => setState(() => _selected = r.$1)),
                  _NavTile(
                    label: 'Custom Report',
                    selected: _selected == 'custom',
                    onTap: () => setState(() => _selected = 'custom'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _selected == 'custom'
                ? const _CustomReportNotice()
                : GridView.count(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.3,
                    children: [
                      for (final r in _reportTypes)
                        if (_selected == 'all' || _selected == r.$1) _ReportCard(type: r.$1, title: r.$2, subtitle: r.$3, icon: r.$4),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.navy.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            label,
            style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppTheme.navy : AppTheme.ink, fontSize: 13.5),
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;

  const _ReportCard({required this.type, required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppTheme.accentBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(icon, size: 19, color: AppTheme.accentBlue),
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.push('/reports/$type', extra: title),
              child: const Text('Generate'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomReportNotice extends StatelessWidget {
  const _CustomReportNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        'A custom report builder (choose your own fields/filters) isn\'t available in this build yet — use one of the report types on the left for now.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
      ),
    );
  }
}
