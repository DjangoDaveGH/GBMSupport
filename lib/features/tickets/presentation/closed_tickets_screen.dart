import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart';

enum _DateRange { all, thisMonth, last3Months }

/// Mockup screen 16 — a dedicated screen for closed tickets (its own search
/// + date-range sub-tabs), separate from "My Tickets" per the confirmed
/// scope decision, rather than one more status tab on the main list.
class ClosedTicketsScreen extends ConsumerStatefulWidget {
  const ClosedTicketsScreen({super.key});

  @override
  ConsumerState<ClosedTicketsScreen> createState() => _ClosedTicketsScreenState();
}

class _ClosedTicketsScreenState extends ConsumerState<ClosedTicketsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  _DateRange _range = _DateRange.all;

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

  bool _matchesRange(Ticket t) {
    final closedAt = t.closedAt;
    if (closedAt == null) return _range == _DateRange.all;
    final now = DateTime.now();
    return switch (_range) {
      _DateRange.all => true,
      _DateRange.thisMonth => closedAt.year == now.year && closedAt.month == now.month,
      _DateRange.last3Months => now.difference(closedAt).inDays <= 90,
    };
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final isSupportSide = appUser?.role.isSupportSide ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Closed Tickets'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: appUser == null
          ? const BrandedLoaderCenter()
          : Column(
              children: [
                _buildSearchBar(),
                _buildRangeTabs(),
                Expanded(child: _buildList(appUser, isSupportSide)),
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

  Widget _buildRangeTabs() {
    final tabs = <(_DateRange, String)>[
      (_DateRange.all, 'All'),
      (_DateRange.thisMonth, 'This Month'),
      (_DateRange.last3Months, 'Last 3 Months'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((t) {
            final (range, label) = t;
            final selected = range == _range;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected,
                showCheckmark: false,
                selectedColor: AppTheme.navy,
                labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.ink, fontWeight: FontWeight.w600),
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                onSelected: (_) => setState(() => _range = range),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildList(AppUser appUser, bool isSupportSide) {
    final filter = const TicketFilter(statuses: {TicketStatus.closed});
    final ticketsAsync = ref.watch(ticketListProvider((appUser, filter)));
    final usersAsync = isSupportSide ? ref.watch(allUsersProvider) : null;

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load closed tickets: $e')),
      data: (allTickets) {
        final tickets = allTickets.where(_matchesRange).where(_matchesSearch).toList();
        if (tickets.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            message: 'No closed tickets in this range.',
          );
        }
        final usersById = <String, AppUser>{
          for (final u in usersAsync?.valueOrNull ?? const <AppUser>[]) u.id: u,
        };
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final ticket in tickets)
              isSupportSide
                  ? AdminTicketTile(ticket: ticket, assignee: usersById[ticket.assignedTo])
                  : TicketTile(ticket: ticket),
          ],
        );
      },
    );
  }
}
