import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/dashboard/data/report_pdf_export.dart';
import 'package:hyport/features/dashboard/data/report_providers.dart';
import 'package:hyport/features/dashboard/domain/report_section_data.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';

/// Renders one of the five report types from real live data. The section/
/// row content comes from report_section_data.dart, shared with the PDF
/// export builder so the on-screen view and the exported file never drift
/// apart — see DECISIONS.md ("Reports PDF export"). Ticket data comes from
/// [ticketAnalyticsProvider] (unbounded), not [ticketListProvider] (capped
/// at [ticketPageSize]), so "Total Tickets" and every breakdown below it is
/// a true count. A filter (status/priority/category, via the same
/// TicketFiltersScreen the Ticket Queue uses) plus a title/reference search
/// let the report be scoped to a subset before those figures are computed —
/// PDF export uses that same filtered set, so the exported file matches
/// what's on screen.
class ReportDetailScreen extends ConsumerStatefulWidget {
  final String reportType;
  final String reportLabel;

  const ReportDetailScreen({super.key, required this.reportType, required this.reportLabel});

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  bool _exporting = false;
  final _searchController = TextEditingController();
  String _search = '';
  TicketFilter _filter = const TicketFilter();

  bool _matchesSearch(Ticket t) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return t.title.toLowerCase().contains(q) || t.ticketReference.toLowerCase().contains(q);
  }

  Future<void> _openFilters() async {
    final result = await context.push<TicketFilter>('/tickets/filters', extra: _filter);
    if (result != null && mounted) setState(() => _filter = result);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final uid = ref.read(currentAppUserProvider).valueOrNull?.id;
    if (uid != null) {
      ref.read(reportViewRepositoryProvider).logView(
            viewedBy: uid,
            reportType: widget.reportType,
            reportLabel: widget.reportLabel,
          );
    }
  }

  Future<void> _exportPdf(String uid, List<ReportSectionData> sections) async {
    setState(() => _exporting = true);
    try {
      final url = await ref.read(reportPdfExporterProvider).exportAndUpload(
            uid: uid,
            reportType: widget.reportType,
            reportLabel: widget.reportLabel,
            sections: sections,
          );
      await ref.read(reportViewRepositoryProvider).logView(
            viewedBy: uid,
            reportType: widget.reportType,
            reportLabel: widget.reportLabel,
            pdfUrl: url,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF exported — see Recent Reports to open it.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export PDF: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Color? _rowColor(String sectionTitle, String label) {
    if (sectionTitle != 'Overall') return null;
    if (label == 'SLA Compliance') return AppTheme.accentBlue;
    if (label == 'Currently Overdue') return StatusColors.critical;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const Scaffold(body: BrandedLoaderCenter());

    final ticketsAsync = ref.watch(ticketAnalyticsProvider((appUser, _filter)));
    final usersAsync = ref.watch(allUsersProvider);
    final slaPolicy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reportLabel),
        actions: [
          IconButton(
            onPressed: _openFilters,
            icon: Icon(_filter.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt_rounded),
          ),
          ticketsAsync.maybeWhen(
            data: (tickets) {
              final filtered = tickets.where(_matchesSearch).toList();
              final sections = reportSectionDataFor(widget.reportType, filtered, usersAsync.valueOrNull ?? const [], slaPolicy);
              return IconButton(
                tooltip: 'Export PDF',
                icon: _exporting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
                onPressed: _exporting ? null : () => _exportPdf(appUser.id, sections),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search by title or reference',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _search = '';
                        }),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ticketsAsync.when(
              loading: () => const BrandedLoaderCenter(),
              error: (e, _) => Center(child: Text('Could not load report: $e')),
              data: (tickets) {
                final filtered = tickets.where(_matchesSearch).toList();
                final sections = reportSectionDataFor(widget.reportType, filtered, usersAsync.valueOrNull ?? const [], slaPolicy);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: sections
                      .map((s) => _ReportSection(
                            title: s.title,
                            rows: s.rows.map((r) => _ReportRow(label: r.$1, value: r.$2, valueColor: _rowColor(s.title, r.$1))).toList(),
                          ))
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const _ReportSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReportRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

