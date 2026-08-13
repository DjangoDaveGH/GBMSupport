import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';

/// Enterprise Web Dashboard's Institutions table — real user counts per
/// institution computed the same way as the mobile Institutions screen.
class DesktopInstitutionsScreen extends ConsumerStatefulWidget {
  const DesktopInstitutionsScreen({super.key});

  @override
  ConsumerState<DesktopInstitutionsScreen> createState() => _DesktopInstitutionsScreenState();
}

class _DesktopInstitutionsScreenState extends ConsumerState<DesktopInstitutionsScreen> {
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
          content: SizedBox(
            width: 360,
            child: Column(
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
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(hintText: 'Search institutions…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                ),
              ),
              const SizedBox(width: 12),
              // Same FilledButton-silently-fails-to-paint issue as
              // DesktopTicketDetailScreen's Actions button — this Row is a
              // direct child of a start-aligned Column with no
              // Expanded/stretch upstream giving it a tightly-bounded width.
              // IntrinsicWidth forces the two-pass measure the button needs,
              // without changing its appearance.
              IntrinsicWidth(
                child: FilledButton.icon(onPressed: _showAddDialog, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add Institution')),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: institutionsAsync.when(
              loading: () => const BrandedLoaderCenter(),
              error: (e, _) => Center(child: Text('Could not load institutions: $e')),
              data: (institutions) {
                final userCounts = <String, int>{};
                for (final u in usersAsync.valueOrNull ?? const []) {
                  userCounts[u.institutionId] = (userCounts[u.institutionId] ?? 0) + 1;
                }
                final filtered = institutions.where((i) => _search.isEmpty || i.name.toLowerCase().contains(_search.toLowerCase())).toList();

                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: filtered.isEmpty
                      ? const EmptyState(icon: Icons.account_balance_outlined, message: 'No institutions found.')
                      : SingleChildScrollView(
                          child: DataTable(
                            headingRowHeight: 44,
                            columns: const [
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Type')),
                              DataColumn(label: Text('Users')),
                            ],
                            rows: filtered
                                .map((i) => DataRow(cells: [
                                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                        const Icon(Icons.account_balance_rounded, size: 16, color: AppTheme.accentBlue),
                                        const SizedBox(width: 8),
                                        Text(i.name),
                                      ])),
                                      DataCell(Text(i.type.wireValue)),
                                      DataCell(Text('${userCounts[i.id] ?? 0}')),
                                    ]))
                                .toList(),
                          ),
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
