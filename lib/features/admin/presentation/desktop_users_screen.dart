import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/auth/domain/institution.dart';
import 'package:intl/intl.dart';

/// Phase 5 mockup screen 36 — same allUsersProvider data as the mobile
/// Users screen, as a sortable/paginated table instead of a card list.
class DesktopUsersScreen extends ConsumerStatefulWidget {
  const DesktopUsersScreen({super.key});

  @override
  ConsumerState<DesktopUsersScreen> createState() => _DesktopUsersScreenState();
}

class _DesktopUsersScreenState extends ConsumerState<DesktopUsersScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  UserRole? _role;
  int _page = 0;
  static const _pageSize = 10;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    final institutionsAsync = ref.watch(institutionListProvider);

    return usersAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load users: $e')),
      data: (users) {
        final institutionsById = <String, Institution>{for (final i in institutionsAsync.valueOrNull ?? const <Institution>[]) i.id: i};

        var filtered = users.where((u) {
          if (_role != null && u.role != _role) return false;
          if (_search.isEmpty) return true;
          final q = _search.toLowerCase();
          return u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);
        }).toList();
        filtered.sort((a, b) => a.name.compareTo(b.name));

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
                      decoration: const InputDecoration(hintText: 'Search users…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    constraints: const BoxConstraints(minWidth: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<UserRole?>(
                        hint: const Text('Role'),
                        isDense: true,
                        value: _role,
                        items: [
                          const DropdownMenuItem<UserRole?>(value: null, child: Text('All Roles')),
                          ...UserRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))),
                        ],
                        onChanged: (v) => setState(() {
                          _role = v;
                          _page = 0;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => context.push('/admin/users/new'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add User'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: filtered.isEmpty
                      ? const EmptyState(icon: Icons.people_outline_rounded, message: 'No users match.')
                      : Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowHeight: 44,
                                    dataRowMinHeight: 56,
                                    dataRowMaxHeight: 56,
                                    columns: const [
                                      DataColumn(label: Text('Name')),
                                      DataColumn(label: Text('Email')),
                                      DataColumn(label: Text('Role')),
                                      DataColumn(label: Text('Institution')),
                                      DataColumn(label: Text('Status')),
                                      DataColumn(label: Text('Last Active')),
                                    ],
                                    rows: pageItems.map((u) => _row(context, u, institutionsById)).toList(),
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
                                  IconButton(
                                    onPressed: page < totalPages - 1 ? () => setState(() => _page = page + 1) : null,
                                    icon: const Icon(Icons.chevron_right_rounded),
                                  ),
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

  DataRow _row(BuildContext context, AppUser u, Map<String, Institution> institutionsById) {
    final online = u.isRecentlyActive;
    return DataRow(cells: [
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
          child: Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?', style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800, fontSize: 11)),
        ),
        const SizedBox(width: 10),
        Text(u.name),
      ])),
      DataCell(Text(u.email)),
      DataCell(Text(u.role.label)),
      DataCell(Text(institutionsById[u.institutionId]?.name ?? u.institutionType.wireValue)),
      DataCell(Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (u.isActive ? StatusColors.resolved : Theme.of(context).colorScheme.outline).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          u.isActive ? 'Active' : 'Inactive',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: u.isActive ? StatusColors.resolved : Theme.of(context).colorScheme.outline),
        ),
      )),
      DataCell(Text(online ? 'Online now' : (u.lastActiveAt == null ? '—' : DateFormat.yMMMd().format(u.lastActiveAt!)))),
    ]);
  }
}
