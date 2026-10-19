import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/models/support_system.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart'
    show AdminTicketTile;

/// Complete requester-centric history. Assignment is intentionally not part
/// of the query: a user's tickets may be distributed across many assignees.
class UserTicketHistoryScreen extends ConsumerStatefulWidget {
  final String userId;

  const UserTicketHistoryScreen({super.key, required this.userId});

  @override
  ConsumerState<UserTicketHistoryScreen> createState() =>
      _UserTicketHistoryScreenState();
}

class _UserTicketHistoryScreenState
    extends ConsumerState<UserTicketHistoryScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  TicketStatus? _status;
  String? _system;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewer = ref.watch(currentAppUserProvider).valueOrNull;
    final usersAsync = ref.watch(allUsersProvider);
    if (viewer == null) return const BrandedLoaderCenter();

    final historyAsync = ref.watch(
      ticketAnalyticsProvider((viewer, TicketFilter(createdBy: widget.userId))),
    );

    return usersAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (error, _) => Center(child: Text('Could not load user: $error')),
      data: (users) {
        final user = users.where((u) => u.id == widget.userId).firstOrNull;
        if (user == null) {
          return const EmptyState(
            icon: Icons.person_search_outlined,
            message: 'User not found.',
          );
        }
        final usersById = <String, AppUser>{
          for (final item in users) item.id: item,
        };

        return historyAsync.when(
          loading: () => const BrandedLoaderCenter(),
          error: (error, _) =>
              Center(child: Text('Could not load ticket history: $error')),
          data: (tickets) => _buildHistory(context, user, tickets, usersById),
        );
      },
    );
  }

  Widget _buildHistory(
    BuildContext context,
    AppUser user,
    List<Ticket> tickets,
    Map<String, AppUser> usersById,
  ) {
    final filtered = tickets.where((ticket) {
      if (_status != null && ticket.status != _status) return false;
      if (_system != null && ticket.system != _system) return false;
      if (_search.isEmpty) return true;
      final query = _search.toLowerCase();
      return ticket.ticketReference.toLowerCase().contains(query) ||
          ticket.title.toLowerCase().contains(query) ||
          ticket.description.toLowerCase().contains(query);
    }).toList();
    final open = tickets.where((t) => t.status.isOpenState).length;
    final resolved = tickets
        .where(
          (t) =>
              {TicketStatus.resolved, TicketStatus.closed}.contains(t.status),
        )
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${user.name} · Ticket History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _UserHeader(user: user, total: tickets.length),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(label: 'All tickets', value: tickets.length),
              _Metric(label: 'Open', value: open),
              _Metric(label: 'Resolved/closed', value: resolved),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: 'Search this user’s tickets…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip('All', _status == null, () {
                setState(() => _status = null);
              }),
              for (final status in [
                TicketStatus.open,
                TicketStatus.inProgress,
                TicketStatus.resolved,
                TicketStatus.closed,
              ])
                _filterChip(status.label, _status == status, () {
                  setState(() => _status = status);
                }),
              DropdownButton<String?>(
                value: _system,
                hint: const Text('All products'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All products'),
                  ),
                  for (final system in supportSystemIds)
                    DropdownMenuItem(
                      value: system,
                      child: Text(supportSystemLabel(system)),
                    ),
                ],
                onChanged: (value) => setState(() => _system = value),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            const EmptyState(
              icon: Icons.confirmation_number_outlined,
              message: 'No tickets match these filters.',
            )
          else
            for (final ticket in filtered)
              AdminTicketTile(
                ticket: ticket,
                assignee: usersById[ticket.assignedTo],
              ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppTheme.navy,
      labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.ink),
      onSelected: (_) => onSelected(),
    );
  }
}

class _UserHeader extends StatelessWidget {
  final AppUser user;
  final int total;

  const _UserHeader({required this.user, required this.total});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
          child: Text(
            user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
            style: const TextStyle(color: AppTheme.navy),
          ),
        ),
        title: Text(user.name),
        subtitle: Text('${user.email} · ${user.role.shortLabel}'),
        trailing: Text('$total total'),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Chip(
    avatar: CircleAvatar(
      backgroundColor: AppTheme.navy,
      child: Text('$value', style: const TextStyle(color: Colors.white)),
    ),
    label: Text(label),
  );
}
