import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/routing/app_shell.dart';
import 'package:hyport/core/routing/desktop_shell.dart';
import 'package:hyport/core/routing/not_found_screen.dart';
import 'package:hyport/core/services/last_route_service.dart';
import 'package:hyport/features/admin/presentation/add_user_screen.dart';
import 'package:hyport/features/admin/presentation/announcements_screen.dart';
import 'package:hyport/features/admin/presentation/desktop_institutions_screen.dart';
import 'package:hyport/features/admin/presentation/desktop_users_screen.dart';
import 'package:hyport/features/admin/presentation/users_screen.dart';
import 'package:hyport/features/auth/presentation/forgot_password_screen.dart';
import 'package:hyport/features/auth/presentation/login_screen.dart';
import 'package:hyport/features/auth/presentation/request_access_screen.dart';
import 'package:hyport/features/auth/presentation/reset_password_screen.dart';
import 'package:hyport/features/auth/presentation/splash_screen.dart';
import 'package:hyport/features/auth/presentation/welcome_screen.dart';
import 'package:hyport/features/auth/presentation/guest_support_screen.dart';
import 'package:hyport/features/auth/presentation/system_audience_screen.dart';
import 'package:hyport/features/admin/presentation/admin_settings_screen.dart';
import 'package:hyport/features/admin/presentation/assignment_rules_screen.dart';
import 'package:hyport/features/admin/presentation/desktop_settings_screen.dart';
import 'package:hyport/features/admin/presentation/institutions_screen.dart';
import 'package:hyport/features/admin/presentation/sla_management_screen.dart';
import 'package:hyport/features/admin/presentation/ticket_settings_screen.dart';
import 'package:hyport/features/dashboard/presentation/analytics_screen.dart';
import 'package:hyport/features/dashboard/presentation/desktop_analytics_screen.dart';
import 'package:hyport/features/dashboard/presentation/desktop_audit_logs_screen.dart';
import 'package:hyport/features/dashboard/presentation/desktop_dashboard_screen.dart';
import 'package:hyport/features/dashboard/domain/report_section_data.dart'
    show reportTypeLabels;
import 'package:hyport/features/dashboard/presentation/home_screen.dart';
import 'package:hyport/features/dashboard/presentation/desktop_reports_screen.dart';
import 'package:hyport/features/dashboard/presentation/report_detail_screen.dart';
import 'package:hyport/features/dashboard/presentation/reports_screen.dart';
import 'package:hyport/features/dashboard/presentation/system_status_screen.dart';
import 'package:hyport/features/knowledge_base/presentation/article_detail_screen.dart';
import 'package:hyport/features/knowledge_base/presentation/article_editor_screen.dart';
import 'package:hyport/features/knowledge_base/presentation/desktop_knowledge_base_screen.dart';
import 'package:hyport/features/knowledge_base/presentation/knowledge_base_screen.dart';
import 'package:hyport/features/notifications/presentation/notifications_screen.dart';
import 'package:hyport/features/profile/presentation/profile_screen.dart';
import 'package:hyport/features/profile/presentation/settings_screen.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/presentation/assign_ticket_screen.dart';
import 'package:hyport/features/tickets/presentation/closed_tickets_screen.dart';
import 'package:hyport/features/tickets/presentation/desktop_assignments_screen.dart';
import 'package:hyport/features/tickets/presentation/desktop_sla_monitoring_screen.dart';
import 'package:hyport/features/tickets/presentation/desktop_ticket_detail_screen.dart';
import 'package:hyport/features/tickets/presentation/desktop_ticket_list_screen.dart';
import 'package:hyport/features/tickets/presentation/new_ticket_screen.dart';
import 'package:hyport/features/tickets/presentation/ticket_chat_screen.dart';
import 'package:hyport/features/tickets/presentation/ticket_detail_screen.dart';
import 'package:hyport/features/tickets/presentation/ticket_filters_screen.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart';
import 'package:hyport/core/widgets/hex_pattern.dart';

/// Ticks whenever auth or profile state changes in a way the redirect cares
/// about, so go_router re-evaluates it (go_router doesn't watch providers on
/// its own).
class GoRouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// A plain Provider, deliberately not a ChangeNotifierProvider: that would
/// tell its dependents to rebuild on every notifyListeners(), and routerProvider
/// depends on this — so each tick would build a brand-new GoRouter at
/// '/splash', throwing away the whole navigation stack (the "randomly jumps
/// back to the dashboard" glitch). The router only needs to *listen* to this
/// via refreshListenable, never rebuild from it.
final _goRouterRefreshProvider = Provider<GoRouterRefreshNotifier>((ref) {
  final notifier = GoRouterRefreshNotifier();
  ref.onDispose(notifier.dispose);
  // touchLastActive on sign-in used to be stamped here too; it now lives
  // solely in PresenceHeartbeatListener (main.dart), which also keeps it
  // moving forward for the rest of the session — see its doc comment.
  ref.listen(authStateChangesProvider, (previous, next) => notifier.notify());
  // The profile doc re-emits on every write to it — the presence heartbeat
  // (~2 min), FCM token registration, an admin edit — none of which change
  // what the redirect reads. Only tick when loading state, identity, role or
  // active status actually differ.
  ref.listen(currentAppUserProvider, (previous, next) {
    final before = previous?.valueOrNull;
    final after = next.valueOrNull;
    final redirectInputsChanged =
        previous == null ||
        previous.isLoading != next.isLoading ||
        before?.id != after?.id ||
        before?.role != after?.role ||
        before?.isActive != after?.isActive;
    if (redirectInputsChanged) notifier.notify();
  });
  return notifier;
});

const supportSideOnlyPaths = [
  '/analytics',
  '/reports',
  '/assignments',
  '/sla-monitoring',
  '/audit-logs',
];
// Everything under /admin-settings (SLA, Assignment Rules, Ticket Settings,
// Announcements) is PFM-Management-only server-side (config/{docId}'s write
// rule and adminBroadcastNotification's own role check both require
// pfm_management) — this must match that boundary, not the broader
// hasBackOfficeAccess set, or a Support Coordinator/Lead can open a screen
// whose save action always fails.
const adminOnlyPaths = ['/admin', '/admin-settings'];

/// True when [location] is [base] itself or a sub-path of it — a segment
/// boundary check, unlike a bare startsWith (which would also treat e.g.
/// '/administrator' as being under '/admin').
bool _isUnder(String location, String base) =>
    location == base || location.startsWith('$base/');

/// `extra` is an untyped Object? and doesn't survive a web reload / browser
/// history restore intact — a hard `as TicketFilter?` cast would throw
/// instead of just opening the screen unfiltered.
TicketFilter? _filterFrom(Object? extra) =>
    extra is TicketFilter ? extra : null;

TicketFilter? _filterWithSystem(TicketFilter? filter, String? system) {
  if (system == null) return filter;
  return TicketFilter(
    system: system,
    systems: filter?.systems ?? const {},
    statuses: filter?.statuses ?? const {},
    category: filter?.category,
    priorities: filter?.priorities ?? const {},
    institutionId: filter?.institutionId,
    institutionType: filter?.institutionType,
    createdAfter: filter?.createdAfter,
    createdBefore: filter?.createdBefore,
    overdueOnly: filter?.overdueOnly ?? false,
  );
}

TicketFilter _coordinatorProductFilter(TicketFilter? filter) => TicketFilter(
  systems: const {'ghaneps', 'gifmis'},
  statuses: filter?.statuses ?? const {},
  category: filter?.category,
  priorities: filter?.priorities ?? const {},
  institutionId: filter?.institutionId,
  institutionType: filter?.institutionType,
  createdAfter: filter?.createdAfter,
  createdBefore: filter?.createdBefore,
  overdueOnly: filter?.overdueOnly ?? false,
);

/// Quick crossfade for the bottom-nav tabs — a horizontal slide (the go_router/
/// platform default) reads wrong for switching between sibling tabs rather
/// than drilling into a new screen.
CustomTransitionPage _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: _brandedRouteSurface(child),
    transitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeOutCubic).animate(animation),
        child: child,
      );
    },
  );
}

/// Subtle slide-up + fade for screens pushed on top of the shell (ticket
/// detail, new ticket, article editor, admin) — signals "drilling in"
/// rather than a lateral tab switch.
CustomTransitionPage _slideUpPage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: _brandedRouteSurface(child),
    transitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Makes the shared hex texture available to every routed screen. Scaffolds
/// inherit a transparent canvas here; screens that intentionally use a solid
/// surface can still opt into one explicitly.
Widget _brandedRouteSurface(Widget child) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: theme.appBarTheme.copyWith(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        child: AppBackground(child: child),
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  // read, not watch — see _goRouterRefreshProvider.
  final refreshNotifier = ref.read(_goRouterRefreshProvider);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    errorBuilder: (context, state) =>
        _brandedRouteSurface(const NotFoundScreen()),
    redirect: (context, state) async {
      final location = state.matchedLocation;
      final onSplash = location == '/splash';
      final preAuthPaths = [
        '/welcome',
        '/login',
        '/forgot-password',
        '/reset-password',
        '/request-access',
      ];
      final onGuestPath = location.startsWith('/guest/');
      final onSupportPath = location.startsWith('/support/');
      final onPreAuthPath =
          preAuthPaths.contains(location) || onGuestPath || onSupportPath;

      final authState = ref.read(authStateChangesProvider);
      if (authState.isLoading) {
        return onSplash ? null : '/splash';
      }

      final firebaseUser = authState.valueOrNull;
      if (firebaseUser == null) {
        // Wipe any resumable location so a later sign-in on this device
        // (same person or someone else) never drops into a screen left over
        // from this session.
        LastRouteService.clear();
        return onPreAuthPath ? null : '/welcome';
      }

      final appUserAsync = ref.read(currentAppUserProvider);
      if (appUserAsync.isLoading) return null;

      final appUser = appUserAsync.valueOrNull;
      if (appUser != null && !appUser.isActive) {
        // A real (not missing/erroring) profile that's explicitly
        // deactivated — end the Auth session too, not just the client-side
        // gate below, so a disabled account doesn't keep a live, valid
        // token on the device indefinitely (anything that ever authorizes
        // off request.auth.uid presence alone would otherwise still let it
        // through). Fire-and-forget: the redirect itself doesn't wait on
        // it, and repeat calls while it's in flight are harmless no-ops.
        ref.read(authServiceProvider).signOut();
      }
      if (appUser == null || !appUser.isActive) {
        return onPreAuthPath ? null : '/login';
      }

      if (onSplash) {
        // Landing on splash while already signed in means either the very
        // first launch, or Android reclaimed the process in the background
        // and this is really a cold start rather than a deliberate relaunch
        // — those look identical to the app. Resume wherever the user last
        // was instead of always dropping them back on the dashboard.
        // Waits for LastRouteService's own (bounded) init rather than
        // racing it — otherwise a slow disk/first run reads as "nothing
        // saved" and silently falls back to /home instead of resuming.
        await LastRouteService.ensureInitialized();
        final resumed = LastRouteService.restore();
        if (resumed != null &&
            resumed != location &&
            !preAuthPaths.contains(resumed)) {
          return resumed;
        }
        return '/home';
      }
      // '/' isn't a route of its own — send it (and go_router's stock error
      // page's "home" button, which targets it) to the dashboard.
      if (onPreAuthPath || location == '/') {
        final selectedSystem = state.uri.queryParameters['system'];
        if (location == '/login' &&
            (selectedSystem == 'ghaneps' || selectedSystem == 'gifmis')) {
          return '/home?system=$selectedSystem';
        }
        return '/home';
      }

      if (supportSideOnlyPaths.any((p) => _isUnder(location, p)) &&
          !appUser.role.hasBackOfficeAccess) {
        return '/home';
      }
      if (adminOnlyPaths.any((p) => _isUnder(location, p)) &&
          appUser.role != UserRole.pfmManagement) {
        return '/home';
      }
      // AssignTicketScreen has no role check of its own — it relies on the
      // ticket detail screens never linking to it for anyone but Support
      // Coordinator and PFM Management/Administrator (canAssign in both
      // ticket_detail_screen.dart and desktop_ticket_detail_screen.dart) and
      // on firestore.rules blocking the write itself. That leaves a
      // direct-URL gap: anyone else could still open this screen and hit a
      // confusing permission-denied write instead of never seeing it.
      // Redirect at the door instead, matching what the UI already implies.
      if (location.startsWith('/tickets/') &&
          location.endsWith('/assign') &&
          appUser.role != UserRole.supportCoordinator &&
          appUser.role != UserRole.pfmManagement) {
        return '/home';
      }
      // Same direct-URL gap as above: firestore.rules' tickets `allow
      // create` only ever admits isRequesterSide() (MDA/MMDA User, Focal
      // Person). AppShell already hides the "+" FAB for every other role,
      // but that's just the UI entry point — redirect at the door too, so
      // a support-side role can't reach the wizard via a direct URL and
      // hit a permission-denied write after filling it out.
      if (location == '/tickets/new' &&
          appUser.role != UserRole.endUser &&
          appUser.role != UserRole.focalPerson) {
        return '/home';
      }
      // Same direct-URL gap for the article editor: knowledge_articles'
      // `allow create` is isSupportSide() only, and the KB screens already
      // hide "New Article" for anyone without back-office access — but
      // that's just the entry point, so a requester (or Vendor) opening the
      // URL would fill it out and hit a permission-denied write.
      if (location == '/knowledge-base/new' &&
          !appUser.role.hasBackOfficeAccess) {
        return '/home';
      }
      // Reached only once this location has cleared every guard above, i.e.
      // it's actually about to be shown — safe to remember as where to
      // resume on the next cold start.
      LastRouteService.save(location);
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => _fadePage(state, const SplashScreen()),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) =>
            _fadePage(state, const WelcomeScreen()),
      ),
      GoRoute(
        path: '/support/:product',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          SystemAudienceScreen(
            product: state.pathParameters['product'] ?? 'ghaneps',
          ),
        ),
      ),
      GoRoute(
        path: '/guest/:product',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          GuestSupportScreen(
            product: state.pathParameters['product'] ?? 'ghaneps',
            ticketReference: state.uri.queryParameters['ticket'],
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadePage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) =>
            _slideUpPage(state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          ResetPasswordScreen(oobCode: state.uri.queryParameters['oobCode']),
        ),
      ),
      GoRoute(
        path: '/request-access',
        pageBuilder: (context, state) =>
            _slideUpPage(state, const RequestAccessScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _fadePage(
              state,
              ResponsiveScreen(
                mobile: HomeScreen(
                  initialSystem: state.uri.queryParameters['system'],
                ),
                desktop: DesktopDashboardScreen(
                  initialSystem: state.uri.queryParameters['system'],
                ),
                desktopTitle:
                    ref.read(currentAppUserProvider).valueOrNull?.role ==
                        UserRole.supportCoordinator
                    ? 'GHANEPS & GIFMIS Support Dashboard'
                    : state.uri.queryParameters['system'] == null
                    ? 'Dashboard'
                    : '${state.uri.queryParameters['system']!.toUpperCase()} Support Dashboard',
              ),
            ),
          ),
          GoRoute(
            path: '/tickets',
            pageBuilder: (context, state) {
              final requestedFilter = _filterWithSystem(
                _filterFrom(state.extra),
                state.uri.queryParameters['system'],
              );
              final isCoordinator =
                  ref.read(currentAppUserProvider).valueOrNull?.role ==
                  UserRole.supportCoordinator;
              final initialFilter = isCoordinator
                  ? _coordinatorProductFilter(requestedFilter)
                  : requestedFilter;
              return _fadePage(
                state,
                ResponsiveScreen(
                  mobile: TicketListScreen(initialFilter: initialFilter),
                  desktop: DesktopTicketListScreen(
                    initialFilter: initialFilter,
                  ),
                  desktopTitle: 'Tickets',
                ),
              );
            },
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) => _fadePage(
              state,
              ResponsiveScreen(
                mobile: const NotificationsScreen(),
                desktop: const Padding(
                  padding: EdgeInsets.all(24),
                  child: NotificationsScreen(embedded: true),
                ),
                desktopTitle: 'Notifications',
              ),
            ),
          ),
          GoRoute(
            path: '/knowledge-base',
            pageBuilder: (context, state) => _fadePage(
              state,
              const ResponsiveScreen(
                mobile: KnowledgeBaseScreen(),
                desktop: DesktopKnowledgeBaseScreen(),
                desktopTitle: 'Knowledge Base',
              ),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => _fadePage(
              state,
              ResponsiveScreen(
                mobile: const ProfileScreen(),
                desktop: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: const ProfileScreen(),
                  ),
                ),
                desktopTitle: 'Profile',
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/tickets/new',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          NewTicketScreen(initialSystem: state.uri.queryParameters['system']),
        ),
      ),
      GoRoute(
        path: '/tickets/filters',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          TicketFiltersScreen(
            initialFilter: _filterFrom(state.extra) ?? const TicketFilter(),
          ),
        ),
      ),
      GoRoute(
        path: '/tickets/closed',
        pageBuilder: (context, state) =>
            _slideUpPage(state, const ClosedTicketsScreen()),
      ),
      GoRoute(
        path: '/tickets/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _slideUpPage(
            state,
            ResponsiveScreen(
              mobile: TicketDetailScreen(ticketId: id),
              desktop: DesktopTicketDetailScreen(ticketId: id),
              desktopTitle: 'Ticket Details',
            ),
          );
        },
      ),
      GoRoute(
        path: '/tickets/:id/chat',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _slideUpPage(state, TicketChatScreen(ticketId: id));
        },
      ),
      GoRoute(
        path: '/tickets/:id/assign',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _slideUpPage(
            state,
            ResponsiveScreen(
              mobile: AssignTicketScreen(ticketId: id),
              desktop: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: AssignTicketScreen(ticketId: id, embedded: true),
                ),
              ),
              desktopTitle: 'Assign Ticket',
            ),
          );
        },
      ),
      GoRoute(
        path: '/assignments',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          ResponsiveScreen(
            mobile: Scaffold(
              appBar: AppBar(title: const Text('Assignments')),
              body: const DesktopAssignmentsScreen(),
            ),
            desktop: const DesktopAssignmentsScreen(),
            desktopTitle: 'Assignments',
          ),
        ),
      ),
      GoRoute(
        path: '/sla-monitoring',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          ResponsiveScreen(
            mobile: Scaffold(
              appBar: AppBar(title: const Text('SLA Monitoring')),
              body: const DesktopSlaMonitoringScreen(),
            ),
            desktop: const DesktopSlaMonitoringScreen(),
            desktopTitle: 'SLA Monitoring',
          ),
        ),
      ),
      GoRoute(
        path: '/audit-logs',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          ResponsiveScreen(
            mobile: Scaffold(
              appBar: AppBar(title: const Text('Audit Logs')),
              body: const DesktopAuditLogsScreen(),
            ),
            desktop: const DesktopAuditLogsScreen(),
            desktopTitle: 'Audit Logs',
          ),
        ),
      ),
      GoRoute(
        path: '/analytics',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: AnalyticsScreen(),
            desktop: DesktopAnalyticsScreen(),
            desktopTitle: 'Analytics',
          ),
        ),
      ),
      GoRoute(
        path: '/reports',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: ReportsScreen(),
            desktop: DesktopReportsScreen(),
            desktopTitle: 'Reports',
          ),
        ),
      ),
      GoRoute(
        path: '/reports/:type',
        // reportSectionDataFor quietly falls back to the summary for an
        // unknown type — under a wrong/blank title. Don't render that.
        redirect: (context, state) =>
            reportTypeLabels.containsKey(state.pathParameters['type'])
            ? null
            : '/reports',
        pageBuilder: (context, state) {
          final reportType = state.pathParameters['type']!;
          final reportLabel = reportTypeLabels[reportType]!;
          final page = ReportDetailScreen(
            reportType: reportType,
            reportLabel: reportLabel,
          );
          return _slideUpPage(
            state,
            ResponsiveScreen(
              mobile: page,
              desktop: Padding(padding: const EdgeInsets.all(24), child: page),
              desktopTitle: reportLabel,
            ),
          );
        },
      ),
      GoRoute(
        path: '/admin-settings',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: AdminSettingsScreen(),
            desktop: DesktopSettingsScreen(),
            desktopTitle: 'Settings',
          ),
        ),
      ),
      GoRoute(
        path: '/admin-settings/sla',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: SlaManagementScreen(),
            desktop: Padding(
              padding: EdgeInsets.all(24),
              child: SlaManagementScreen(),
            ),
            desktopTitle: 'SLA Management',
          ),
        ),
      ),
      GoRoute(
        path: '/admin-settings/assignment',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: AssignmentRulesScreen(),
            desktop: Padding(
              padding: EdgeInsets.all(24),
              child: AssignmentRulesScreen(),
            ),
            desktopTitle: 'Auto-Assignment',
          ),
        ),
      ),
      GoRoute(
        path: '/admin-settings/tickets',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: TicketSettingsScreen(),
            desktop: Padding(
              padding: EdgeInsets.all(24),
              child: TicketSettingsScreen(),
            ),
            desktopTitle: 'Ticket Settings',
          ),
        ),
      ),
      GoRoute(
        path: '/admin-settings/announcements',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: AnnouncementsScreen(),
            desktop: Padding(
              padding: EdgeInsets.all(24),
              child: AnnouncementsScreen(),
            ),
            desktopTitle: 'Announcements',
          ),
        ),
      ),
      GoRoute(
        path: '/admin/institutions',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: InstitutionsScreen(),
            desktop: DesktopInstitutionsScreen(),
            desktopTitle: 'Institutions',
          ),
        ),
      ),
      GoRoute(
        path: '/knowledge-base/new',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          ResponsiveScreen(
            mobile: const ArticleEditorScreen(),
            desktop: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const ArticleEditorScreen(embedded: true),
              ),
            ),
            desktopTitle: 'New Article',
          ),
        ),
      ),
      GoRoute(
        path: '/knowledge-base/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _slideUpPage(
            state,
            ResponsiveScreen(
              mobile: ArticleDetailScreen(articleId: id),
              desktop: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ArticleDetailScreen(articleId: id, embedded: true),
                ),
              ),
              desktopTitle: 'Article',
            ),
          );
        },
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          ResponsiveScreen(
            mobile: const SettingsScreen(),
            desktop: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: const SettingsScreen(embedded: true),
              ),
            ),
            desktopTitle: 'Settings',
          ),
        ),
      ),
      GoRoute(
        path: '/system-status',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          ResponsiveScreen(
            mobile: const SystemStatusScreen(),
            desktop: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: const SystemStatusScreen(embedded: true),
              ),
            ),
            desktopTitle: 'System Status',
          ),
        ),
      ),
      GoRoute(
        path: '/admin/users',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          const ResponsiveScreen(
            mobile: UsersScreen(),
            desktop: DesktopUsersScreen(),
            desktopTitle: 'Users',
          ),
        ),
      ),
      GoRoute(
        path: '/admin/users/new',
        pageBuilder: (context, state) => _slideUpPage(
          state,
          ResponsiveScreen(
            mobile: const AddUserScreen(),
            desktop: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: const AddUserScreen(embedded: true),
              ),
            ),
            desktopTitle: 'Add User',
          ),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
