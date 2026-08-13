import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/responsive.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/notifications/data/notification_providers.dart';
import 'package:hyport/core/widgets/pwa_install_button.dart';

/// Picks [desktop] (wrapped in the persistent `DesktopShell` chrome) for
/// support-side roles on a wide viewport, [mobile] otherwise — the one
/// switch every responsive route in app_router.dart goes through, so no
/// individual screen has to know about the other's existence.
class ResponsiveScreen extends ConsumerWidget {
  final Widget mobile;
  final Widget desktop;
  final String desktopTitle;

  const ResponsiveScreen({
    super.key,
    required this.mobile,
    required this.desktop,
    required this.desktopTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    // hasBackOfficeAccess (not the broader isSupportSide) — Vendor/Specialist
    // stays on the mobile UI even at desktop widths, since none of the
    // Phase 5 mockups show a Vendor-scoped desktop view and their
    // permissions are deliberately narrower than back-office staff.
    final isBackOffice = appUser?.role.hasBackOfficeAccess ?? false;
    if (isDesktopWidth(context) && isBackOffice) {
      return DesktopShell(title: desktopTitle, child: desktop);
    }
    return mobile;
  }
}

class _NavItem {
  final String path;
  final IconData icon;
  final String label;
  final bool pfmManagementOnly;

  const _NavItem(
    this.path,
    this.icon,
    this.label, {
    this.pfmManagementOnly = false,
  });
}

const _navItems = [
  _NavItem('/home', Icons.dashboard_outlined, 'Dashboard'),
  _NavItem('/tickets', Icons.confirmation_number_outlined, 'Tickets'),
  _NavItem('/assignments', Icons.assignment_ind_outlined, 'Assignments'),
  _NavItem('/knowledge-base', Icons.menu_book_outlined, 'Knowledge Base'),
  _NavItem('/reports', Icons.description_outlined, 'Reports'),
  _NavItem('/analytics', Icons.bar_chart_outlined, 'Analytics'),
  _NavItem(
    '/admin/users',
    Icons.people_outline_rounded,
    'Users',
    pfmManagementOnly: true,
  ),
  _NavItem(
    '/admin/institutions',
    Icons.account_balance_outlined,
    'Institutions',
    pfmManagementOnly: true,
  ),
  _NavItem('/sla-monitoring', Icons.gpp_good_outlined, 'SLA Monitoring'),
  _NavItem(
    '/admin-settings',
    Icons.settings_outlined,
    'Settings',
    pfmManagementOnly: true,
  ),
  _NavItem('/audit-logs', Icons.fact_check_outlined, 'Audit Logs'),
];

/// The Enterprise Web Dashboard's persistent chrome — sidebar + top bar —
/// wrapping every desktop-width screen for support-side roles (Phase 5
/// mockup screens 30-40 all share this exact frame). See core/responsive.dart
/// for the width/role gate that decides mobile vs. this.
class DesktopShell extends ConsumerWidget {
  final Widget child;
  final String title;

  const DesktopShell({super.key, required this.child, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final isPfmManagement = appUser?.role == UserRole.pfmManagement;
    final unread = appUser == null
        ? 0
        : ref.watch(unreadNotificationCountProvider(appUser.id));
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      backgroundColor: AppTheme.mist,
      body: Row(
        children: [
          _Sidebar(currentLocation: location, isPfmManagement: isPfmManagement),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(title: title, appUser: appUser, unread: unread),
                Expanded(
                  // No screen here was designed to stretch arbitrarily wide —
                  // on an ultra-wide monitor (2560px+), stat cards and charts
                  // (e.g. DesktopDashboardScreen's _StatCard row) end up
                  // stretched into oddly disproportionate shapes with no
                  // upper bound. Cap at a width comfortably past a typical
                  // 1920px monitor (1920 - 224px sidebar = 1696, under this
                  // cap) so nothing changes there; only wider displays get
                  // centered instead of stretched.
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1800),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String currentLocation;
  final bool isPfmManagement;

  const _Sidebar({
    required this.currentLocation,
    required this.isPfmManagement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      color: AppTheme.navyDarkest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/mof_logo.png',
                  width: 34,
                  height: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PFMSD',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.gold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const Text(
                        'Support Centre',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _navItems
                  .where((n) => !n.pfmManagementOnly || isPfmManagement)
                  .map((item) {
                    final selected =
                        currentLocation == item.path ||
                        currentLocation.startsWith('${item.path}/');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          onTap: () => context.go(item.path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.icon,
                                  size: 18,
                                  color: selected
                                      ? AppTheme.gold
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final AppUser? appUser;
  final int unread;

  const _TopBar({
    required this.title,
    required this.appUser,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GBMS SUPPORT CENTRE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.navy,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 2),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const Spacer(),
          const PwaInstallButton(compact: true),
          IconButton(
            onPressed: () => context.push('/notifications'),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (unread > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: StatusColors.critical,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: () => context.push('/profile'),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.navy.withValues(alpha: 0.12),
                child: Text(
                  (appUser == null || appUser!.name.isEmpty)
                      ? '?'
                      : appUser!.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
