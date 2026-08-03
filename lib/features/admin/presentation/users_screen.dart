import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

enum _UserTab { all, supportOfficers, mdas }

const _supportOfficerRoles = {
  UserRole.supportCoordinator,
  UserRole.functionalLead,
  UserRole.technicalLead,
  UserRole.pfmManagement,
  UserRole.vendorSupport,
};
const _mdaRoles = {UserRole.mdaUser, UserRole.focalPerson};

/// Admin app screen 25 — PFM Management only (see adminOnlyPaths). Every
/// count and online dot here is real: online/offline is a coarse
/// "active within the last 5 minutes" derived from AppUser.lastActiveAt
/// (stamped once per sign-in — see UserRepository.touchLastActive), not a
/// live presence system.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  _UserTab _tab = _UserTab.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesTab(AppUser u) => switch (_tab) {
        _UserTab.all => true,
        _UserTab.supportOfficers => _supportOfficerRoles.contains(u.role),
        _UserTab.mdas => _mdaRoles.contains(u.role),
      };

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/users/new'),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add User'),
      ),
      body: usersAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Center(child: Text('Could not load users: $e')),
        data: (users) {
          final supportCount = users.where((u) => _supportOfficerRoles.contains(u.role)).length;
          final mdaCount = users.where((u) => _mdaRoles.contains(u.role)).length;
          final filtered = users
              .where(_matchesTab)
              .where((u) => _search.isEmpty || u.name.toLowerCase().contains(_search) || u.email.toLowerCase().contains(_search))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: const InputDecoration(hintText: 'Search users…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _tabChip('All (${users.length})', _UserTab.all),
                      const SizedBox(width: 8),
                      _tabChip('Support Officers ($supportCount)', _UserTab.supportOfficers),
                      const SizedBox(width: 8),
                      _tabChip('MDAs ($mdaCount)', _UserTab.mdas),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(icon: Icons.people_outline_rounded, message: 'No users match.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _UserTile(user: filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tabChip(String label, _UserTab tab) {
    final selected = tab == _tab;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppTheme.navy,
      labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.ink, fontWeight: FontWeight.w600),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      onSelected: (_) => setState(() => _tab = tab),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AppUser user;

  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final online = user.isRecentlyActive;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: online ? StatusColors.resolved : Theme.of(context).colorScheme.outline,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: Theme.of(context).textTheme.titleSmall),
                Text(user.role.label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            online ? 'Online' : 'Offline',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: online ? StatusColors.resolved : Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
