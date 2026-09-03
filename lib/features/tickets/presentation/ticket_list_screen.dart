import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/draft_ticket.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:intl/intl.dart';
import 'package:hyport/core/widgets/branded_loader.dart';

/// Top chip presets (mockup screen 13: All/Open/In Progress/Resolved/
/// Closed). "Closed" is handled separately — tapping it navigates to the
/// dedicated Closed Tickets screen rather than filtering in place — so it
/// isn't part of this preset map.
enum StatusTab { all, open, inProgress, resolved }

Set<TicketStatus> statusesForTab(StatusTab tab) => switch (tab) {
      StatusTab.all => const {},
      StatusTab.open => const {TicketStatus.open},
      StatusTab.inProgress => const {TicketStatus.inProgress, TicketStatus.escalated},
      StatusTab.resolved => const {TicketStatus.resolved},
    };

bool setEquals<T>(Set<T> a, Set<T> b) => a.length == b.length && a.every(b.contains);

class TicketListScreen extends ConsumerStatefulWidget {
  const TicketListScreen({super.key});

  @override
  ConsumerState<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends ConsumerState<TicketListScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  Set<TicketStatus> _statuses = {};
  TicketCategory? _category;
  Set<TicketPriority> _priorities = {};
  String? _institutionId;
  InstitutionType? _institutionType;
  DateTime? _createdAfter;
  DateTime? _createdBefore;
  bool _overdueOnly = false;

  bool get _hasAdvancedFilters =>
      _category != null ||
      _priorities.isNotEmpty ||
      _institutionId != null ||
      _institutionType != null ||
      _createdAfter != null ||
      _createdBefore != null ||
      _overdueOnly;

  /// Current filter state — re-seeds the Filters screen and drives
  /// [TicketFilter.matchesClientSide]. Search is applied separately.
  TicketFilter get _filter => TicketFilter(
        statuses: _statuses,
        category: _category,
        priorities: _priorities,
        institutionId: _institutionId,
        institutionType: _institutionType,
        createdAfter: _createdAfter,
        createdBefore: _createdBefore,
        overdueOnly: _overdueOnly,
      );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Ticket t) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return t.title.toLowerCase().contains(q) || t.ticketReference.toLowerCase().contains(q);
  }

  Future<void> _openFilters() async {
    final result = await context.push<TicketFilter>('/tickets/filters', extra: _filter);
    if (result != null && mounted) {
      setState(() {
        _statuses = result.statuses;
        _category = result.category;
        _priorities = result.priorities;
        _institutionId = result.institutionId;
        _institutionType = result.institutionType;
        _createdAfter = result.createdAfter;
        _createdBefore = result.createdBefore;
        _overdueOnly = result.overdueOnly;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final isSupportSide = appUser?.role.isSupportSide ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(isSupportSide ? 'Ticket Queue' : 'My Tickets'),
        actions: [
          IconButton(
            onPressed: _openFilters,
            icon: Icon(_hasAdvancedFilters ? Icons.filter_alt_rounded : Icons.filter_alt_outlined),
          ),
        ],
      ),
      body: appUser == null
          ? const BrandedLoaderCenter()
          : Column(
              children: [
                _buildSearchBar(),
                Expanded(child: _buildDraftsAndTickets(appUser, isSupportSide)),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
    );
  }

  Widget _buildTabs(List<Ticket> allTickets) {
    final counts = <StatusTab, int>{
      for (final tab in StatusTab.values)
        tab: tab == StatusTab.all
            ? allTickets.length
            : allTickets.where((t) => statusesForTab(tab).contains(t.status)).length,
    };
    final closedCount = allTickets.where((t) => t.status == TicketStatus.closed).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in StatusTab.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _TabChip(
                  label: '${_tabLabel(tab)} (${counts[tab]})',
                  selected: setEquals(_statuses, statusesForTab(tab)),
                  onTap: () => setState(() => _statuses = statusesForTab(tab)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _TabChip(
                label: 'Closed ($closedCount)',
                selected: false,
                onTap: () => context.push('/tickets/closed'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tabLabel(StatusTab tab) => switch (tab) {
        StatusTab.all => 'All',
        StatusTab.open => 'Open',
        StatusTab.inProgress => 'In Progress',
        StatusTab.resolved => 'Resolved',
      };

  Widget _buildDraftsAndTickets(AppUser appUser, bool isSupportSide) {
    // Fetched without a status filter so the tab chips above can show a
    // count per status; the active status set is then applied client-side.
    // Uses the unbounded ticketAnalyticsProvider (not ticketListProvider,
    // which pages at ticketPageSize) so both the tab counts and the list
    // itself reflect every matching ticket, not just the most recent page.
    //
    // Only the query-backed filters go to the provider; institution / date /
    // overdue are applied in memory below (TicketFilter.matchesClientSide) so
    // they never change the Firestore query or its family cache key.
    final countsFilter = TicketFilter(category: _category, priorities: _priorities);
    final ticketsAsync = ref.watch(ticketAnalyticsProvider((appUser, countsFilter)));
    final slaPolicy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();
    final institutionTypes = {
      for (final i in [...?ref.watch(institutionListProvider).valueOrNull]) i.id: i.type,
    };
    final draftRepo = ref.watch(draftTicketRepositoryProvider);
    final drafts = draftRepo.getAllForUser(appUser.id).where((d) => d.pendingSync).toList();
    final usersAsync = isSupportSide ? ref.watch(allUsersProvider) : null;

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load tickets: $e')),
      data: (rawTickets) {
        // Narrow by the advanced filters first so the status tab counts
        // below reflect them too.
        final allTickets = rawTickets
            .where((t) => _filter.matchesClientSide(t, policy: slaPolicy, institutionTypes: institutionTypes))
            .toList();
        final tabs = _buildTabs(allTickets);
        final tickets = allTickets
            .where((t) => _statuses.isEmpty || _statuses.contains(t.status))
            .where(_matchesSearch)
            .toList();
        final hasActiveFilters = _statuses.isNotEmpty || _search.isNotEmpty || _hasAdvancedFilters;

        if (tickets.isEmpty && drafts.isEmpty) {
          return Column(
            children: [
              tabs,
              Expanded(
                child: EmptyState(
                  icon: Icons.confirmation_number_outlined,
                  message: hasActiveFilters
                      ? 'No tickets match these filters.'
                      : (isSupportSide ? 'No tickets have come in yet.' : 'No tickets yet. Tap "New Ticket" to log an issue.'),
                  badgeIcon: hasActiveFilters ? null : Icons.add_rounded,
                ),
              ),
            ],
          );
        }

        final usersById = <String, AppUser>{
          for (final u in usersAsync?.valueOrNull ?? const <AppUser>[]) u.id: u,
        };

        return Column(
          children: [
            tabs,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  for (final draft in drafts) DraftTile(draft: draft),
                  for (final ticket in tickets)
                    isSupportSide
                        ? AdminTicketTile(ticket: ticket, assignee: usersById[ticket.assignedTo])
                        : TicketTile(ticket: ticket),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppTheme.navy,
      labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.ink, fontWeight: FontWeight.w600),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      onSelected: (_) => onTap(),
    );
  }
}

IconData categoryIcon(TicketCategory category) => switch (category) {
      TicketCategory.access => Icons.key_rounded,
      TicketCategory.workflow => Icons.alt_route_rounded,
      TicketCategory.budgetForms => Icons.description_rounded,
      TicketCategory.reports => Icons.summarize_rounded,
      TicketCategory.smartView => Icons.grid_view_rounded,
      TicketCategory.businessRules => Icons.rule_rounded,
      TicketCategory.metadata => Icons.account_tree_rounded,
      TicketCategory.dataValidation => Icons.fact_check_rounded,
      TicketCategory.essbase => Icons.dns_rounded,
      TicketCategory.systemPerformance => Icons.speed_rounded,
      TicketCategory.mobileAppIssue => Icons.phone_iphone_rounded,
      TicketCategory.generalEnquiry => Icons.help_outline_rounded,
    };

class DraftTile extends StatelessWidget {
  final DraftTicket draft;

  const DraftTile({super.key, required this.draft});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.cloud_off_rounded, size: 19, color: AppTheme.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(draft.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text('Pending — will submit when online', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            DateFormat.MMMd().format(draft.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Mockup screen 13's ticket row: reference, a status pill top-right,
/// title, then priority + relative time.
class TicketTile extends StatelessWidget {
  final Ticket ticket;

  const TicketTile({super.key, required this.ticket});

  Color get _priorityColor => switch (ticket.priority) {
        TicketPriority.critical => StatusColors.critical,
        TicketPriority.high => StatusColors.high,
        TicketPriority.medium => StatusColors.medium,
        TicketPriority.low => StatusColors.low,
      };

  @override
  Widget build(BuildContext context) {
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
          onTap: () => context.push('/tickets/${ticket.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('#${ticket.ticketReference}', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    TicketStatusChip(status: ticket.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(ticket.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      ticket.priority.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: _priorityColor),
                    ),
                    const Spacer(),
                    Text(_relativeTimeShort(ticket.createdAt), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phase 4 mockup screen 20's row shape — priority + title up top, then
/// who it's assigned to (or "Unassigned") and when, instead of the
/// requester tile's category icon (assignment matters more to support
/// staff scanning a queue than category does).
class AdminTicketTile extends StatelessWidget {
  final Ticket ticket;
  final AppUser? assignee;

  const AdminTicketTile({super.key, required this.ticket, required this.assignee});

  Color get _priorityColor => switch (ticket.priority) {
        TicketPriority.critical => StatusColors.critical,
        TicketPriority.high => StatusColors.high,
        TicketPriority.medium => StatusColors.medium,
        TicketPriority.low => StatusColors.low,
      };

  @override
  Widget build(BuildContext context) {
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
          onTap: () => context.push('/tickets/${ticket.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('#${ticket.ticketReference}', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    TicketStatusChip(status: ticket.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(ticket.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: assignee == null
                          ? Theme.of(context).colorScheme.surfaceContainerHigh
                          : AppTheme.navy.withValues(alpha: 0.1),
                      child: assignee == null
                          ? Icon(Icons.person_off_outlined, size: 13, color: Theme.of(context).colorScheme.outline)
                          : Text(
                              assignee!.name.isNotEmpty ? assignee!.name[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        assignee?.name ?? 'Unassigned',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      ticket.priority.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: _priorityColor),
                    ),
                    const SizedBox(width: 8),
                    Text(_relativeTimeShort(ticket.createdAt), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _relativeTimeShort(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.MMMd().format(dt);
}
