import 'package:flutter/material.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// Static for the MVP — Section 7 scopes "system downtime" as an
/// admin-triggered broadcast notification, not a live health-check
/// integration with GBMS's actual infrastructure (that would
/// need a monitoring feed this app has no access to). This screen shows
/// the intended layout with all services reporting operational; wiring it
/// to a real status feed is future work — see DECISIONS.md.
class SystemStatusScreen extends StatelessWidget {
  /// When true, renders just the list content with no Scaffold/AppBar of
  /// its own — for embedding inside DesktopShell. See NotificationsScreen's
  /// doc comment for why.
  final bool embedded;

  const SystemStatusScreen({super.key, this.embedded = false});

  static const _services = [
    'GBMS Application',
    'Essbase Server',
    'Smart View',
    'Reports & Dashboards',
    'Workflow Engine',
    'Database',
  ];

  @override
  Widget build(BuildContext context) {
    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('All systems operational', style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        'Last updated: just now',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ..._services.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(s, style: Theme.of(context).textTheme.bodyMedium)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_rounded, size: 13, color: AppTheme.success),
                          const SizedBox(width: 4),
                          Text('Operational', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.success)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: AppSpacing.md),
          Text(
            'If you are experiencing issues while all systems are operational, please create a ticket and our team will assist you.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('System Status')), body: body);
  }
}
