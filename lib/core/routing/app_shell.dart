import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/responsive.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/pwa_install_button.dart';

/// Bottom-nav shell. Both requester and support-side roles get the
/// reference design's split bar with a raised gold center "+" button —
/// Create Ticket for requesters, and the same action for support-side
/// staff logging a ticket on a caller's behalf (Phase 4 mockup's Admin
/// Dashboard/Tickets/+/Alerts/Profile bar). Support-side roles reach
/// Analytics/Reports/Users/Institutions/Knowledge Base/Settings via the
/// Dashboard screen's drawer (see the ☰ icon in that mockup) rather than
/// the bottom bar, which only has room for 4 primary destinations + FAB.
///
/// On a desktop-width viewport, back-office roles skip this chrome
/// entirely — `ResponsiveScreen` (desktop_shell.dart) wraps the routed
/// child in `DesktopShell`'s sidebar instead (Phase 5), so this widget
/// just passes `child` through unwrapped rather than double-shelling it
/// behind a bottom nav bar that would otherwise still render underneath.
class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  static const _tabs = ['/home', '/tickets', '/notifications', '/profile'];
  static const _supportTabs = [
    '/home',
    '/tickets',
    '/notifications',
    '/profile',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final isSupportSide = appUser?.role.hasBackOfficeAccess ?? false;

    if (isDesktopWidth(context) && isSupportSide) return child;

    final tabs = isSupportSide ? _supportTabs : _tabs;

    final location = GoRouterState.of(context).matchedLocation;
    var currentIndex = tabs.indexOf(location);
    if (currentIndex == -1) currentIndex = 0;

    return Scaffold(
      body: Stack(
        children: [
          child,
          const Positioned(
            right: 16,
            bottom: 88,
            child: SafeArea(child: PwaInstallButton()),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        tabs: tabs,
        currentIndex: currentIndex,
        isSupportSide: isSupportSide,
        onTap: (i) => context.go(tabs[i]),
        onCenterAction: () => context.push('/tickets/new'),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final bool isSupportSide;
  final ValueChanged<int> onTap;
  final VoidCallback onCenterAction;

  const _BottomBar({
    required this.tabs,
    required this.currentIndex,
    required this.isSupportSide,
    required this.onTap,
    required this.onCenterAction,
  });

  // Labels differ slightly by role to match each mockup exactly: the User
  // Mobile App (Phase 3) bar reads "Home / Notifications"; the Admin
  // Mobile App (Phase 4) bar reads "Dashboard / Alerts" for the same two
  // destinations.
  //
  // Icons are the real reference-asset PNGs rather than Material icons —
  // each is a single two-tone (navy + light-blue) glyph, not an outline/
  // filled pair, so selected vs. unselected is expressed with opacity
  // instead of icon-swapping.
  static const _icons = {
    '/home': ('assets/images/icon_home.png', 'Home'),
    '/tickets': ('assets/images/icon_tickets.png', 'Tickets'),
    '/notifications': ('assets/images/icon_notifications.png', 'Notifications'),
    '/knowledge-base': ('assets/images/icon_knowledge_base.png', 'Knowledge'),
    '/profile': ('assets/images/icon_profile.png', 'Profile'),
  };

  static const _supportLabelOverrides = {
    '/home': 'Dashboard',
    '/notifications': 'Alerts',
  };

  @override
  Widget build(BuildContext context) {
    // Split around a raised center FAB — same bar shape for both roles,
    // just a different tab set feeding it.
    final midpoint = (tabs.length / 2).ceil();
    final leftTabs = tabs.sublist(0, midpoint);
    final rightTabs = tabs.sublist(midpoint);

    // Unlike the built-in Material BottomNavigationBar, this bar is a plain
    // Stack/Container, so it doesn't automatically reserve space for
    // Android's system nav bar (3-button or gesture) the way that widget
    // does — without this, the tab row renders underneath the system keys
    // on real devices. Grow the bar by that inset and push the tab row up
    // by the same amount, so the white card still extends all the way to
    // the true bottom of the screen (no gap) while the tappable icons/
    // labels sit above the system bar.
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: 72 + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            top: 12,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg),
                ),
                boxShadow: softShadow(opacity: 0.05),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Row(
                  children: [
                    ...leftTabs.map((t) => _tabButton(context, t)),
                    const Expanded(child: SizedBox()),
                    ...rightTabs.map((t) => _tabButton(context, t)),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: GestureDetector(
              onTap: onCenterAction,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.navy,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.navy.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(BuildContext context, String path) {
    final index = tabs.indexOf(path);
    final selected = index == currentIndex;
    final (iconAsset, defaultLabel) = _icons[path]!;
    final label = isSupportSide
        ? (_supportLabelOverrides[path] ?? defaultLabel)
        : defaultLabel;
    final color = selected
        ? AppTheme.navy
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: selected ? 1 : 0.45,
                child: Image.asset(iconAsset, width: 22, height: 22),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 9.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
