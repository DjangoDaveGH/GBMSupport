import 'package:flutter/material.dart';
import 'package:hyport/features/dashboard/data/report_export.dart';

/// "Download" button that offers every [ReportFormat]. Shows a spinner
/// while [busy]. [compact] renders an app-bar icon instead of a labelled
/// button.
class ReportDownloadMenu extends StatelessWidget {
  final bool busy;
  final bool compact;
  final ValueChanged<ReportFormat> onSelected;

  const ReportDownloadMenu({
    super.key,
    required this.busy,
    required this.onSelected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    return PopupMenuButton<ReportFormat>(
      enabled: !busy,
      tooltip: 'Download report',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final f in ReportFormat.values)
          PopupMenuItem(
            value: f,
            child: Row(
              children: [
                Icon(f.icon, size: 20),
                const SizedBox(width: 12),
                Text(f.label),
              ],
            ),
          ),
      ],
      child: compact
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: busy ? spinner : const Icon(Icons.download_rounded),
            )
          : IgnorePointer(
              child: FilledButton.icon(
                onPressed: busy ? null : () {},
                icon: busy ? spinner : const Icon(Icons.download_rounded),
                label: const Text('Download report'),
              ),
            ),
    );
  }
}
