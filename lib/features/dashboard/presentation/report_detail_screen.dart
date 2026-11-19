import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/models/support_system.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/app_error_state.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/dashboard/data/report_export.dart';
import 'package:hyport/features/dashboard/data/report_providers.dart';
import 'package:hyport/features/dashboard/domain/report_section_data.dart';
import 'package:hyport/features/dashboard/presentation/report_download_menu.dart';
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
/// Downloads (PDF, Word, PowerPoint, CSV — see report_export.dart) use
/// that same filtered set, so the file matches what's on screen.
class ReportDetailScreen extends ConsumerStatefulWidget {
  final String reportType;
  final String reportLabel;

  const ReportDetailScreen({
    super.key,
    required this.reportType,
    required this.reportLabel,
  });

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
    return t.title.toLowerCase().contains(q) ||
        t.ticketReference.toLowerCase().contains(q);
  }

  Future<void> _openFilters() async {
    final result = await context.push<TicketFilter>(
      '/tickets/filters',
      extra: _effectiveFilter,
    );
    if (result != null && mounted) setState(() => _filter = result);
  }

  TicketFilter get _effectiveFilter {
    final uri = GoRouterState.of(context).uri;
    final selectedSystem = uri.queryParameters['system'];
    final appUser = ref.read(currentAppUserProvider).valueOrNull;
    return TicketFilter(
      system: selectedSystem,
      systems:
          selectedSystem == null && appUser?.role == UserRole.supportCoordinator
          ? allowedSystemsForRole(appUser!.role, appUser.systems)
          : const {},
      statuses: _filter.statuses,
      priorities: _filter.priorities,
      category: _filter.category,
      institutionId: _filter.institutionId,
      institutionType: _filter.institutionType,
      createdAfter: _filter.createdAfter,
      createdBefore: _filter.createdBefore,
      overdueOnly: _filter.overdueOnly,
    );
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
      ref
          .read(reportViewRepositoryProvider)
          .logView(
            viewedBy: uid,
            reportType: widget.reportType,
            reportLabel: widget.reportLabel,
          );
    }
  }

  /// What the downloaded file was scoped to, so it says so on the page.
  List<String> _scopeLines(TicketFilter filter) {
    final system = filter.system;
    return [
      if (system != null) 'System: ${system.toUpperCase()}',
      if (filter.statuses.isNotEmpty ||
          filter.priorities.isNotEmpty ||
          filter.category != null ||
          filter.overdueOnly ||
          filter.createdAfter != null ||
          filter.createdBefore != null)
        'Filters applied',
      if (_search.isNotEmpty) 'Search: "$_search"',
    ];
  }

  Future<void> _export(
    ReportFormat format,
    String uid,
    List<ReportSectionData> sections,
    TicketFilter filter,
  ) async {
    setState(() => _exporting = true);
    try {
      await ref
          .read(reportExporterProvider)
          .export(
            format: format,
            uid: uid,
            reportType: widget.reportType,
            reportLabel: widget.reportLabel,
            sections: sections,
            subtitleLines: _scopeLines(filter),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${format.label} downloaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not download ${format.label}: $e')),
      );
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

    final effectiveFilter = _effectiveFilter;
    final ticketsAsync = ref.watch(
      ticketAnalyticsProvider((appUser, effectiveFilter)),
    );
    final usersAsync = ref.watch(allUsersProvider);
    final slaPolicy =
        ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reportLabel),
        actions: [
          IconButton(
            onPressed: _openFilters,
            icon: Icon(
              effectiveFilter.isEmpty
                  ? Icons.filter_alt_outlined
                  : Icons.filter_alt_rounded,
            ),
          ),
          ticketsAsync.maybeWhen(
            data: (tickets) {
              final filtered = tickets.where(_matchesSearch).toList();
              final sections = reportSectionDataFor(
                widget.reportType,
                filtered,
                usersAsync.valueOrNull ?? const [],
                slaPolicy,
              );
              return ReportDownloadMenu(
                compact: true,
                busy: _exporting,
                onSelected: (format) =>
                    _export(format, appUser.id, sections, effectiveFilter),
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
              error: (e, _) => const AppErrorState(
                message: 'We could not load this report.',
              ),
              data: (tickets) {
                final filtered = tickets.where(_matchesSearch).toList();
                final sections = reportSectionDataFor(
                  widget.reportType,
                  filtered,
                  usersAsync.valueOrNull ?? const [],
                  slaPolicy,
                );
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: sections
                      .map(
                        (s) => _ReportSection(
                          title: s.title,
                          rows: s.rows
                              .map(
                                (r) => _ReportRow(
                                  label: r.$1,
                                  value: r.$2,
                                  valueColor: _rowColor(s.title, r.$1),
                                ),
                              )
                              .toList(),
                        ),
                      )
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
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
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
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}
