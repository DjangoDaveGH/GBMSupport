import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/dashboard/data/audit_log_providers.dart';
import 'package:hyport/features/dashboard/domain/audit_log_formatting.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';
import 'package:intl/intl.dart';

String _describe(TicketActivity a, String ticketRef) {
  final prefix = '#$ticketRef';
  switch (a.action) {
    case TicketActivityAction.created:
      return '$prefix created';
    case TicketActivityAction.assigned:
      return '$prefix assigned';
    case TicketActivityAction.statusChanged:
      return '$prefix status changed: ${a.fromValue} → ${a.toValue}';
    case TicketActivityAction.escalated:
      return '$prefix escalated';
    case TicketActivityAction.commented:
      return '$prefix comment added';
    case TicketActivityAction.reopened:
      return '$prefix reopened';
    case TicketActivityAction.closed:
      return '$prefix closed';
  }
}

String _actionLabel(TicketActivityAction action) => switch (action) {
      TicketActivityAction.created => 'Created Ticket',
      TicketActivityAction.assigned => 'Assigned Ticket',
      TicketActivityAction.statusChanged => 'Updated Status',
      TicketActivityAction.escalated => 'Escalated Ticket',
      TicketActivityAction.commented => 'Sent Chat Message',
      TicketActivityAction.reopened => 'Reopened Ticket',
      TicketActivityAction.closed => 'Closed Ticket',
    };

/// Phase 5 mockup screen 40. See AuditLogRepository's doc comment for the
/// honest scope of what this covers: ticket lifecycle events (via a real
/// collectionGroup query) for every back-office role, plus — for PFM
/// Management/Administrator only, per FR-SEC-03 ("only Administrators may
/// view the audit log") — a second tab of user-management actions written
/// by the adminCreateUser/adminUpdateUser Cloud Functions. Not a full
/// system audit trail (no login events or settings changes), since that
/// would need Cloud Functions this project can't deploy yet.
class DesktopAuditLogsScreen extends ConsumerStatefulWidget {
  const DesktopAuditLogsScreen({super.key});

  @override
  ConsumerState<DesktopAuditLogsScreen> createState() => _DesktopAuditLogsScreenState();
}

class _DesktopAuditLogsScreenState extends ConsumerState<DesktopAuditLogsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  String? _userFilter;
  TicketActivityAction? _actionFilter;
  int _page = 0;
  bool _showAdminActions = false;
  static const _pageSize = 15;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _exportCsv(List<TicketActivity> entries, Map<String, AppUser> usersById, Map<String, Ticket> ticketsById) {
    final buffer = StringBuffer('Date,User,Action,Details\n');
    for (final a in entries) {
      final user = usersById[a.actorId]?.name ?? a.actorId;
      final ticketRef = ticketsById[a.ticketId]?.ticketReference ?? a.ticketId;
      buffer.writeln('"${DateFormat.yMd().add_jms().format(a.timestamp)}","$user","${_actionLabel(a.action)}","${_describe(a, ticketRef).replaceAll('"', '""')}"');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${entries.length} rows as CSV to clipboard.')));
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const BrandedLoaderCenter();
    final isAdmin = appUser.role == UserRole.pfmManagement;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Ticket Activity')),
                ButtonSegment(value: true, label: Text('Admin Actions')),
              ],
              selected: {_showAdminActions},
              onSelectionChanged: (s) => setState(() {
                _showAdminActions = s.first;
                _page = 0;
              }),
            ),
          ),
        Expanded(
          child: (isAdmin && _showAdminActions) ? _buildAdminActionsTab(context) : _buildTicketActivityTab(context, appUser),
        ),
      ],
    );
  }

  Widget _buildTicketActivityTab(BuildContext context, AppUser appUser) {
    final logAsync = ref.watch(auditLogProvider);
    final usersAsync = ref.watch(allUsersProvider);
    final ticketsAsync = ref.watch(ticketListProvider((appUser, const TicketFilter())));

    return logAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load audit log: $e')),
      data: (entries) {
        final usersById = <String, AppUser>{for (final u in usersAsync.valueOrNull ?? const <AppUser>[]) u.id: u};
        final ticketsById = <String, Ticket>{for (final t in ticketsAsync.valueOrNull ?? const <Ticket>[]) t.id: t};

        var filtered = entries.where((a) {
          if (_userFilter != null && a.actorId != _userFilter) return false;
          if (_actionFilter != null && a.action != _actionFilter) return false;
          if (_search.isNotEmpty) {
            final ticketRef = ticketsById[a.ticketId]?.ticketReference ?? '';
            final q = _search.toLowerCase();
            if (!ticketRef.toLowerCase().contains(q) && !(a.note ?? '').toLowerCase().contains(q)) return false;
          }
          return true;
        }).toList();

        final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 999999);
        final page = _page.clamp(0, totalPages - 1);
        final pageItems = filtered.skip(page * _pageSize).take(_pageSize).toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() {
                        _search = v;
                        _page = 0;
                      }),
                      decoration: const InputDecoration(hintText: 'Search logs…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    constraints: const BoxConstraints(minWidth: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<TicketActivityAction?>(
                        hint: const Text('Action'),
                        isDense: true,
                        value: _actionFilter,
                        items: [
                          const DropdownMenuItem<TicketActivityAction?>(value: null, child: Text('All Actions')),
                          ...TicketActivityAction.values.map((a) => DropdownMenuItem(value: a, child: Text(_actionLabel(a)))),
                        ],
                        onChanged: (v) => setState(() {
                          _actionFilter = v;
                          _page = 0;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    constraints: const BoxConstraints(minWidth: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        hint: const Text('User'),
                        isDense: true,
                        value: _userFilter,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Users')),
                          ...usersById.values.map((u) => DropdownMenuItem(value: u.id, child: Text(u.name))),
                        ],
                        onChanged: (v) => setState(() {
                          _userFilter = v;
                          _page = 0;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered, usersById, ticketsById),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                  child: filtered.isEmpty
                      ? const EmptyState(icon: Icons.fact_check_outlined, message: 'No matching log entries.')
                      : Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowHeight: 44,
                                    columns: const [
                                      DataColumn(label: Text('Date & Time')),
                                      DataColumn(label: Text('User')),
                                      DataColumn(label: Text('Action')),
                                      DataColumn(label: Text('Details')),
                                    ],
                                    rows: pageItems.map((a) {
                                      final user = usersById[a.actorId];
                                      final ticketRef = ticketsById[a.ticketId]?.ticketReference ?? a.ticketId;
                                      return DataRow(
                                        onSelectChanged: a.ticketId.isEmpty ? null : (_) => context.push('/tickets/${a.ticketId}'),
                                        cells: [
                                          DataCell(Text(DateFormat.yMd().add_jms().format(a.timestamp))),
                                          DataCell(Text(user?.name ?? 'Unknown')),
                                          DataCell(Text(_actionLabel(a.action))),
                                          DataCell(SizedBox(width: 320, child: Text(_describe(a, ticketRef), overflow: TextOverflow.ellipsis))),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(onPressed: page > 0 ? () => setState(() => _page = page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
                                  Text('Page ${page + 1} of $totalPages', style: Theme.of(context).textTheme.bodySmall),
                                  IconButton(onPressed: page < totalPages - 1 ? () => setState(() => _page = page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminActionsTab(BuildContext context) {
    final logAsync = ref.watch(adminActionsAuditLogProvider);
    final usersAsync = ref.watch(allUsersProvider);

    return logAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load admin actions: $e')),
      data: (entries) {
        final usersById = <String, AppUser>{for (final u in usersAsync.valueOrNull ?? const <AppUser>[]) u.id: u};

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
            child: entries.isEmpty
                ? const EmptyState(icon: Icons.admin_panel_settings_outlined, message: 'No admin actions recorded yet.')
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 44,
                        columns: const [
                          DataColumn(label: Text('Date & Time')),
                          DataColumn(label: Text('Admin')),
                          DataColumn(label: Text('Action')),
                          DataColumn(label: Text('Target User')),
                          DataColumn(label: Text('Details')),
                        ],
                        rows: entries.map((a) {
                          final actor = usersById[a.actorId];
                          final target = usersById[a.targetId];
                          final targetName = target?.name ?? a.targetId;
                          return DataRow(cells: [
                            DataCell(Text(DateFormat.yMd().add_jms().format(a.timestamp))),
                            DataCell(Text(actor?.name ?? 'Unknown')),
                            DataCell(Text(adminActionLabel(a.action))),
                            DataCell(Text(targetName)),
                            DataCell(SizedBox(width: 320, child: Text(describeAdminAction(a, targetName), overflow: TextOverflow.ellipsis))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
