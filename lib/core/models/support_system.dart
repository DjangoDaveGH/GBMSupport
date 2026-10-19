import 'package:hyport/core/models/enums.dart';

const supportSystemIds = <String>['gbms', 'ghaneps', 'gifmis'];

/// The operational dashboard workspaces. GBMS is deliberately kept separate
/// from the GHANEPS/GIFMIS support tenant, while management can still inspect
/// everything from one read-only overview.
enum SupportWorkspace { all, gbms, external }

extension SupportWorkspaceX on SupportWorkspace {
  String get label => switch (this) {
    SupportWorkspace.all => 'All Systems',
    SupportWorkspace.gbms => 'GBMS',
    SupportWorkspace.external => 'GHANEPS + GIFMIS',
  };

  Set<String> get systems => switch (this) {
    SupportWorkspace.all => supportSystemIds.toSet(),
    SupportWorkspace.gbms => const {'gbms'},
    SupportWorkspace.external => const {'ghaneps', 'gifmis'},
  };

  /// Query parameter used to preserve the selected workspace across routes.
  String? get routeSystem => switch (this) {
    SupportWorkspace.all => 'all',
    SupportWorkspace.gbms => 'gbms',
    SupportWorkspace.external => 'external',
  };
}

SupportWorkspace workspaceFromRoute(String? system, {required UserRole role}) {
  if (role == UserRole.supportCoordinator) return SupportWorkspace.external;
  return switch (system) {
    'all' => SupportWorkspace.all,
    'gbms' => SupportWorkspace.gbms,
    'external' || 'ghaneps' || 'gifmis' => SupportWorkspace.external,
    _ =>
      role == UserRole.pfmManagement
          ? SupportWorkspace.gbms
          : SupportWorkspace.all,
  };
}

String supportSystemLabel(String id) => switch (id) {
  'gbms' => 'GBMS',
  'ghaneps' => 'GHANEPS',
  'gifmis' => 'GIFMIS',
  _ => id.toUpperCase(),
};

Set<String> defaultSystemsForRole(UserRole role) =>
    role == UserRole.supportCoordinator
    ? const {'ghaneps', 'gifmis'}
    : const {'gbms'};

bool isTenantScopedSupportRole(UserRole role) => switch (role) {
  UserRole.supportCoordinator ||
  UserRole.functionalLead ||
  UserRole.technicalLead ||
  UserRole.vendorSupport => true,
  UserRole.endUser || UserRole.focalPerson || UserRole.pfmManagement => false,
};

/// Systems a support account may query. PFM Management is the tenant-wide
/// administrator; every other support role is limited to its assigned
/// systems. An explicit GBMS assignment therefore stays GBMS-only.
Set<String> allowedSystemsForRole(UserRole role, Iterable<String> systems) {
  if (role == UserRole.pfmManagement) return supportSystemIds.toSet();
  final assigned = systems.where(supportSystemIds.contains).toSet();
  if (isTenantScopedSupportRole(role)) {
    // GBMS and the GHANEPS/GIFMIS workspace are separate support tenants.
    // Be defensive when reading older or manually-migrated profiles.
    if (assigned.contains('gbms')) return const {'gbms'};
    final ppa = assigned.where({'ghaneps', 'gifmis'}.contains).toSet();
    if (ppa.isNotEmpty) return ppa;
  }
  return assigned.isEmpty ? defaultSystemsForRole(role) : assigned;
}

/// Product scope for a Support Coordinator. Older coordinator accounts may
/// have no product list yet, so retain the historical two-product fallback;
/// newly configured single-product accounts stay strictly tenant-scoped to
/// the product assigned by an administrator.
Set<String> coordinatorProductSystems(Iterable<String> systems) {
  return allowedSystemsForRole(UserRole.supportCoordinator, systems);
}

String supportSystemsLabel(Iterable<String> systems) {
  final values = systems.toSet();
  if (values.isEmpty) return 'No systems';
  if (values.length == supportSystemIds.length) return 'All systems';
  return supportSystemIds
      .where(values.contains)
      .map(supportSystemLabel)
      .join(' + ');
}
