import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    var type = InstitutionType.mda;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add Institution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              DropdownButtonFormField<InstitutionType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: InstitutionType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.wireValue))).toList(),
                onChanged: (v) => setDialogState(() => type = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                await ref.read(institutionRepositoryProvider).create(name: name, type: type);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final institutionsAsync = ref.watch(institutionListProvider);
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Institutions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
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
              decoration: const InputDecoration(hintText: 'Search institutions…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            ),
          ),
          Expanded(
            child: institutionsAsync.when(
              loading: () => const BrandedLoaderCenter(),
              error: (e, _) => Center(child: Text('Could not load institutions: $e')),
              data: (institutions) {
                final userCounts = <String, int>{};
                for (final u in usersAsync.valueOrNull ?? const []) {
                  userCounts[u.institutionId] = (userCounts[u.institutionId] ?? 0) + 1;
                }
                final filtered = institutions.where((i) => _search.isEmpty || i.name.toLowerCase().contains(_search)).toList();
                if (filtered.isEmpty) {
                  return const EmptyState(icon: Icons.account_balance_outlined, message: 'No institutions found.');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _InstitutionTile(
                    institution: filtered[i],
                    userCount: userCounts[filtered[i].id] ?? 0,
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
  final int userCount;

  const _InstitutionTile({required this.institution, required this.userCount});

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
            child: const Icon(Icons.account_balance_rounded, size: 19, color: AppTheme.accentBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(institution.name, style: Theme.of(context).textTheme.titleSmall),
                Text(institution.type.wireValue, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text('$userCount Users', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.accentBlue)),
        ],
      ),
    );
  }
}
