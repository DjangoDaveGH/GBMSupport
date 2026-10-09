import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/models/support_system.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/admin/presentation/institution_dialogs.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/institution.dart';

/// Admin app screen 26 — PFM Management only (see adminOnlyPaths). User
/// counts per institution are computed client-side from the real user
/// list grouped by institutionId, not stored/duplicated anywhere.
class InstitutionsScreen extends ConsumerStatefulWidget {
  const InstitutionsScreen({super.key});

  @override
  ConsumerState<InstitutionsScreen> createState() => _InstitutionsScreenState();
}

class _InstitutionsScreenState extends ConsumerState<InstitutionsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  String _selectedSystem = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final institutionsAsync = ref.watch(institutionListProvider);
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Institutions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddInstitutionDialog(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Institution'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search institutions…',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                for (final system in ['all', ...supportSystemIds]) ...[
                  if (system != 'all') const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(
                      system == 'all'
                          ? 'All systems'
                          : supportSystemLabel(system),
                    ),
                    selected: _selectedSystem == system,
                    onSelected: (_) => setState(() => _selectedSystem = system),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: institutionsAsync.when(
              loading: () => const BrandedLoaderCenter(),
              error: (e, _) =>
                  Center(child: Text('Could not load institutions: $e')),
              data: (institutions) {
                final userCounts = <String, Map<String, int>>{};
                for (final u in usersAsync.valueOrNull ?? const []) {
                  if (!u.isActive) continue;
                  final systemCounts = userCounts.putIfAbsent(
                    u.institutionId,
                    () => {for (final system in supportSystemIds) system: 0},
                  );
                  for (final system in u.systems) {
                    if (systemCounts.containsKey(system)) {
                      systemCounts[system] = systemCounts[system]! + 1;
                    }
                  }
                }
                final filtered = institutions.where((institution) {
                  final matchesSearch =
                      _search.isEmpty ||
                      institution.name.toLowerCase().contains(_search);
                  final activeCount =
                      userCounts[institution.id]?[_selectedSystem] ?? 0;
                  return matchesSearch &&
                      (_selectedSystem == 'all' || activeCount > 0);
                }).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.account_balance_outlined,
                    message: _selectedSystem == 'all'
                        ? 'No institutions found.'
                        : 'No institutions with active ${supportSystemLabel(_selectedSystem)} users found.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _InstitutionTile(
                    institution: filtered[i],
                    activeUsersBySystem:
                        userCounts[filtered[i].id] ??
                        {for (final system in supportSystemIds) system: 0},
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InstitutionTile extends StatelessWidget {
  final Institution institution;
  final Map<String, int> activeUsersBySystem;

  const _InstitutionTile({
    required this.institution,
    required this.activeUsersBySystem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.account_balance_rounded,
              size: 19,
              color: AppTheme.accentBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  institution.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  institution.type.wireValue,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Active users by system',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final system in supportSystemIds)
                      _InstitutionSystemCount(
                        system: system,
                        count: activeUsersBySystem[system] ?? 0,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstitutionSystemCount extends StatelessWidget {
  final String system;
  final int count;

  const _InstitutionSystemCount({required this.system, required this.count});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
      backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.08),
      side: BorderSide.none,
      label: Text('${supportSystemLabel(system)} $count'),
    );
  }
}
