import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/dashboard/data/report_export.dart';
import 'package:hyport/features/dashboard/domain/report_csv.dart';
import 'package:hyport/features/dashboard/domain/report_section_data.dart';
import 'package:hyport/features/dashboard/presentation/report_download_menu.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:intl/intl.dart';

/// Admin-only (PFM Management) reports page: every report type, scoped by
/// date range and system, downloadable as PDF, Word, PowerPoint or CSV
/// (plus a raw per-ticket CSV). Route guard lives in
/// app_router.dart (`/admin` prefix), so this screen is not linked for
/// anyone else.
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

enum _DatePreset { last7, last30, last90, thisYear, allTime, custom }

const _datePresetLabels = {
  _DatePreset.last7: 'Last 7 days',
  _DatePreset.last30: 'Last 30 days',
  _DatePreset.last90: 'Last 90 days',
  _DatePreset.thisYear: 'This year',
  _DatePreset.allTime: 'All time',
  _DatePreset.custom: 'Custom…',
};

const _systemOptions = <(String?, String)>[
  (null, 'All systems'),
  ('gbms', 'GBMS'),
  ('ghaneps', 'GHANEPS'),
  ('gifmis', 'GIFMIS'),
];

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  final _dateFmt = DateFormat('d MMM yyyy');

  String _reportType = 'summary';
  String? _system;
  _DatePreset _preset = _DatePreset.last30;
  DateTimeRange? _customRange;
  bool _busy = false;

  /// Resolved inclusive date range, or null for "all time".
  DateTimeRange? _resolveRange(DateTime now) {
    DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = startOfDay(now);
    return switch (_preset) {
      _DatePreset.last7 => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
      _DatePreset.last30 => DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today,
      ),
      _DatePreset.last90 => DateTimeRange(
        start: today.subtract(const Duration(days: 89)),
        end: today,
      ),
      _DatePreset.thisYear => DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: today,
      ),
      _DatePreset.allTime => null,
      _DatePreset.custom => _customRange,
    };
  }

  String _rangeLabel(DateTimeRange? range) => range == null
      ? 'All time'
      : '${_dateFmt.format(range.start)} – ${_dateFmt.format(range.end)}';

  /// Inclusive on both ends: a ticket created any time on the last day counts.
  bool _inRange(Ticket t, DateTimeRange? range) {
    if (range == null) return true;
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final endExclusive = DateTime(
      range.end.year,
      range.end.month,
      range.end.day + 1,
    );
    return !t.createdAt.isBefore(start) && t.createdAt.isBefore(endExclusive);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _preset = _DatePreset.custom;
      });
    }
  }

  Future<void> _download({
    required ReportFormat format,
    required AppUser me,
    required DateTimeRange? range,
    required List<Ticket> tickets,
    required List<ReportSectionData> sections,
    Map<String, String>? ticketCsvUserNames,
  }) async {
    setState(() => _busy = true);
    final typeLabel = reportTypeLabels[_reportType] ?? _reportType;
    final systemLabel = _systemOptions.firstWhere((o) => o.$1 == _system).$2;
    final isTicketList = ticketCsvUserNames != null;
    try {
      await ref
          .read(reportExporterProvider)
          .export(
            format: format,
            uid: me.id,
            reportType: _reportType,
            reportLabel: isTicketList ? 'Tickets List' : typeLabel,
            sections: sections,
            subtitleLines: [_rangeLabel(range), systemLabel],
            csvRows: isTicketList
                ? ticketsToRows(tickets, ticketCsvUserNames)
                : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${format.label} downloaded.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final range = _resolveRange(DateTime.now());
    final ticketsAsync = ref.watch(
      ticketAnalyticsProvider((appUser, TicketFilter(system: _system))),
    );
    final users = ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[];
    final slaPolicy =
        ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();
    final userNames = {for (final u in users) u.id: u.name};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _FilterCard(
          reportType: _reportType,
          onReportType: (v) => setState(() => _reportType = v),
          system: _system,
          onSystem: (v) => setState(() => _system = v),
          preset: _preset,
          customLabel: _customRange == null
              ? null
              : _rangeLabel(_customRange),
          onPreset: (p) {
            if (p == _DatePreset.custom) {
              _pickCustomRange();
            } else {
              setState(() => _preset = p);
            }
          },
        ),
        const SizedBox(height: 16),
        ticketsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load tickets: $e'),
          ),
          data: (all) {
            final tickets = all.where((t) => _inRange(t, range)).toList();
            final sections = reportSectionDataFor(
              _reportType,
              tickets,
              users,
              slaPolicy,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tickets.length} ticket${tickets.length == 1 ? '' : 's'} · ${_rangeLabel(range)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ReportDownloadMenu(
                      busy: _busy,
                      onSelected: (format) => _download(
                        format: format,
                        me: appUser,
                        range: range,
                        tickets: tickets,
                        sections: sections,
                      ),
                    ),
                    _DownloadButton(
                      icon: Icons.list_alt_outlined,
                      label: 'Download tickets CSV',
                      busy: _busy,
                      onPressed: () => _download(
                        format: ReportFormat.csv,
                        me: appUser,
                        range: range,
                        tickets: tickets,
                        sections: sections,
                        ticketCsvUserNames: userNames,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final section in sections) _SectionCard(section: section),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FilterCard extends StatelessWidget {
  final String reportType;
  final ValueChanged<String> onReportType;
  final String? system;
  final ValueChanged<String?> onSystem;
  final _DatePreset preset;
  final String? customLabel;
  final ValueChanged<_DatePreset> onPreset;

  const _FilterCard({
    required this.reportType,
    required this.onReportType,
    required this.system,
    required this.onSystem,
    required this.preset,
    required this.customLabel,
    required this.onPreset,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in reportTypeLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: reportType == e.key,
                  onSelected: (_) => onReportType(e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('System', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in _systemOptions)
                ChoiceChip(
                  label: Text(label),
                  selected: system == value,
                  onSelected: (_) => onSystem(value),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Created', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _DatePreset.values)
                ChoiceChip(
                  label: Text(
                    p == _DatePreset.custom && customLabel != null
                        ? customLabel!
                        : _datePresetLabels[p]!,
                  ),
                  selected: preset == p,
                  onSelected: (_) => onPreset(p),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final ReportSectionData section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (section.rows.isEmpty)
              const Text('No data for this range.')
            else
              for (final (label, value) in section.rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(label)),
                      Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  const _DownloadButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}
