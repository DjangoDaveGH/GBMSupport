import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/routing/app_shell.dart';
import 'package:hyport/core/routing/desktop_shell.dart';
import 'package:hyport/features/admin/presentation/add_user_screen.dart';
import 'package:hyport/features/admin/presentation/desktop_institutions_screen.dart';
import 'package:hyport/features/admin/presentation/desktop_users_screen.dart';
import 'package:hyport/features/admin/presentation/users_screen.dart';
import 'package:hyport/features/auth/presentation/forgot_password_screen.dart';
import 'package:hyport/features/auth/presentation/login_screen.dart';
import 'package:hyport/features/auth/presentation/request_access_screen.dart';
import 'package:hyport/features/auth/presentation/reset_password_screen.dart';
import 'package:hyport/features/auth/presentation/splash_screen.dart';
import 'package:hyport/features/auth/presentation/welcome_screen.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
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

/// Ticks whenever auth or profile state changes, so go_router re-evaluates
/// its redirect logic (go_router doesn't watch providers on its own).
class GoRouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final _goRouterRefreshProvider = ChangeNotifierProvider<GoRouterRefreshNotifier>((ref) {
  final notifier = GoRouterRefreshNotifier();
  ref.listen(authStateChangesProvider, (previous, next) {
    notifier.notify();
    final uid = next.valueOrNull?.uid;
    if (uid != null) {
      ref.read(userRepositoryProvider).touchLastActive(uid);
    }
  });
  ref.listen(currentAppUserProvider, (_, _) => notifier.notify());
  return notifier;
});

const supportSideOnlyPaths = ['/analytics', '/reports', '/admin-settings', '/assignments', '/sla-monitoring', '/audit-logs'];
const adminOnlyPaths = ['/admin'];

/// Quick crossfade for the bottom-nav tabs — a horizontal slide (the go_router/
/// platform default) reads wrong for switching between sibling tabs rather
/// than drilling into a new screen.
CustomTransitionPage _fadePage(Widget child) {
  return CustomTransitionPage(
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: CurveTween(curve: Curves.easeOutCubic).animate(animation), child: child);
    },
  );
}

/// Subtle slide-up + fade for screens pushed on top of the shell (ticket
/// detail, new ticket, article editor, admin) — signals "drilling in"
/// rather than a lateral tab switch.
CustomTransitionPage _slideUpPage(Widget child) {
  return CustomTransitionPage(
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_goRouterRefreshProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final onSplash = location == '/splash';
      final preAuthPaths = ['/welcome', '/login', '/forgot-password', '/reset-password', '/request-access'];
      final onPreAuthPath = preAuthPaths.contains(location);

      final authState = ref.read(authStateChangesProvider);
      if (authState.isLoading) {
        return onSplash ? null : '/splash';
      }

      final firebaseUser = authState.valueOrNull;
      if (firebaseUser == null) {
        return onPreAuthPath ? null : '/welcome';
      }

      final appUserAsync = ref.read(currentAppUserProvider);
      if (appUserAsync.isLoading) return onSplash ? null : null;

      final appUser = appUserAsync.valueOrNull;
      if (appUser == null || !appUser.isActive) {
        return onPreAuthPath ? null : '/login';
      }

      if (onSplash || onPreAuthPath) return '/home';

      if (supportSideOnlyPaths.any(location.startsWith) && !appUser.role.hasBackOfficeAccess) {
        return '/home';
      }
      if (adminOnlyPaths.any(location.startsWith) && appUser.role != UserRole.pfmManagement) {
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
      if (location == '/tickets/new' && appUser.role != UserRole.mdaUser && appUser.role != UserRole.focalPerson) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => _fadePage(const SplashScreen()),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) => _fadePage(const WelcomeScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadePage(const LoginScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => _slideUpPage(const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) =>
            _slideUpPage(ResetPasswordScreen(oobCode: state.uri.queryParameters['oobCode'])),
      ),
      GoRoute(
        path: '/request-access',
        pageBuilder: (context, state) => _slideUpPage(const RequestAccessScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _fadePage(const ResponsiveScreen(
              mobile: HomeScreen(),
              desktop: DesktopDashboardScreen(),
              desktopTitle: 'Dashboard',
            )),
          ),
          GoRoute(
            path: '/tickets',
            pageBuilder: (context, state) {
              final initialFilter = state.extra as TicketFilter?;
              return _fadePage(ResponsiveScreen(
                mobile: TicketListScreen(initialFilter: initialFilter),
                desktop: DesktopTicketListScreen(initialFilter: initialFilter),
                desktopTitle: 'Tickets',
              ));
            },
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) => _fadePage(ResponsiveScreen(
              mobile: const NotificationsScreen(),
              desktop: const Padding(padding: EdgeInsets.all(24), child: NotificationsScreen(embedded: true)),
              desktopTitle: 'Notifications',
            )),
          ),
          GoRoute(
            path: '/knowledge-base',
            pageBuilder: (context, state) => _fadePage(const ResponsiveScreen(
              mobile: KnowledgeBaseScreen(),
              desktop: DesktopKnowledgeBaseScreen(),
              desktopTitle: 'Knowledge Base',
            )),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => _fadePage(ResponsiveScreen(
              mobile: const ProfileScreen(),
              desktop: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: const ProfileScreen())),
              desktopTitle: 'Profile',
            )),
          ),
        ],
      ),
      GoRoute(
        path: '/tickets/new',
        pageBuilder: (context, state) => _slideUpPage(const NewTicketScreen()),
      ),
      GoRoute(
        path: '/tickets/filters',
        pageBuilder: (context, state) => _slideUpPage(
          TicketFiltersScreen(initialFilter: state.extra as TicketFilter? ?? const TicketFilter()),
        ),
      ),
      GoRoute(
        path: '/tickets/closed',
        pageBuilder: (context, state) => _slideUpPage(const ClosedTicketsScreen()),
      ),
      GoRoute(
        path: '/tickets/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _slideUpPage(ResponsiveScreen(
            mobile: TicketDetailScreen(ticketId: id),
            desktop: DesktopTicketDetailScreen(ticketId: id),
            desktopTitle: 'Ticket Details',
          ));
        },
      ),
      GoRoute(
        path: '/tickets/:id/chat',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _slideUpPage(TicketChatScreen(ticketId: id));
        },
      ),
      GoRoute(
        path: '/tickets/:id/assign',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _slideUpPage(ResponsiveScreen(
            mobile: AssignTicketScreen(ticketId: id),
            desktop: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AssignTicketScreen(ticketId: id, embedded: true),
              ),
            ),
            desktopTitle: 'Assign Ticket',
          ));
        },
      ),
      GoRoute(
        path: '/assignments',
        pageBuilder: (context, state) => _slideUpPage(ResponsiveScreen(
          mobile: Scaffold(appBar: AppBar(title: const Text('Assignments')), body: const DesktopAssignmentsScreen()),
          desktop: const DesktopAssignmentsScreen(),
          desktopTitle: 'Assignments',
        )),
      ),
      GoRoute(
        path: '/sla-monitoring',
        pageBuilder: (context, state) => _slideUpPage(ResponsiveScreen(
          mobile: Scaffold(appBar: AppBar(title: const Text('SLA Monitoring')), body: const DesktopSlaMonitoringScreen()),
          desktop: const DesktopSlaMonitoringScreen(),
          desktopTitle: 'SLA Monitoring',
        )),
      ),
      GoRoute(
        path: '/audit-logs',
        pageBuilder: (context, state) => _slideUpPage(ResponsiveScreen(
          mobile: Scaffold(appBar: AppBar(title: const Text('Audit Logs')), body: const DesktopAuditLogsScreen()),
          desktop: const DesktopAuditLogsScreen(),
          desktopTitle: 'Audit Logs',
        )),
      ),
      GoRoute(
        path: '/analytics',
        pageBuilder: (context, state) => _slideUpPage(const ResponsiveScreen(
          mobile: AnalyticsScreen(),
          desktop: DesktopAnalyticsScreen(),
          desktopTitle: 'Analytics',
        )),
      ),
      GoRoute(
        path: '/reports',
        pageBuilder: (context, state) => _slideUpPage(const ResponsiveScreen(
          mobile: ReportsScreen(),
          desktop: DesktopReportsScreen(),
          desktopTitle: 'Reports',
        )),
      ),
      GoRoute(
        path: '/reports/:type',
        pageBuilder: (context, state) {
          final reportType = state.pathParameters['type']!;
          final reportLabel = (state.extra as String?) ?? 'Report';
          final page = ReportDetailScreen(reportType: reportType, reportLabel: reportLabel);
          return _slideUpPage(ResponsiveScreen(
            mobile: page,
            desktop: Padding(padding: const EdgeInsets.all(24), child: page),
            desktopTitle: reportLabel,
          ));
        },
      ),
      GoRoute(
        path: '/admin-settings',
        pageBuilder: (context, state) => _slideUpPage(const ResponsiveScreen(
          mobile: AdminSettingsScreen(),
          desktop: DesktopSettingsScreen(),
          desktopTitle: 'Settings',
        )),
      ),
      GoRoute(
        path: '/admin-settings/sla',
        pageBuilder: (context, state) => _slideUpPage(const ResponsiveScreen(
          mobile: SlaManagementScreen(),
          desktop: Padding(padding: EdgeInsets.all(24), child: SlaManagementScreen()),
          desktopTitle: 'SLA Management',
        )),
      ),
      GoRoute(
        path: '/admin-settings/assignment',
        pageBuilder: (context, state) => _slideUpPage(const ResponsiveScreen(
          mobile: AssignmentRulesScreen(),
          desktop: Padding(padding: EdgeInsets.all(24), child: AssignmentRulesScreen()),
          desktopTitle: 'Auto-Assignment',
        )),
      ),
      GoRoute(
        path: '/admin-settings/tickets',
        pageBuilder: (context, state) => _slideUpPage(const ResponsiveScreen(
          mobile: TicketSettingsScreen(),
          desktop: Padding(padding: EdgeInsets.all(24), child: TicketSettingsScreen()),
          desktopTitle: 'Ticket Settings',
        )),
      ),
      GoRoute(
        path: '/admin/institutions',
        pageBuilder: (context, state) => _slideUpPage(const ResponsiveScreen(
          mobile: InstitutionsScreen(),
          desktop: DesktopInstitutionsScreen(),
          desktopTitle: 'Institutions',
        )),
      ),
      GoRoute(
        path: '/knowledge-base/new',
        pageBuilder: (context, state) => _slideUpPage(ResponsiveScreen(
          mobile: const ArticleEditorScreen(),
          desktop: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: const ArticleEditorScreen(embedded: true),
            ),
          ),
          desktopTitle: 'New Article',
        )),
      ),
      GoRoute(
        path: '/knowledge-base/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _slideUpPage(ResponsiveScreen(
            mobile: ArticleDetailScreen(articleId: id),
            desktop: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ArticleDetailScreen(articleId: id, embedded: true),
              ),
            ),
            desktopTitle: 'Article',
          ));
        },
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _slideUpPage(ResponsiveScreen(
          mobile: const SettingsScreen(),
          desktop: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const SettingsScreen(embedded: true),
            ),
          ),
          desktopTitle: 'Settings',
        )),
      ),
      GoRoute(
        path: '/system-status',
        pageBuilder: (context, state) => _slideUpPage(ResponsiveScreen(
          mobile: const SystemStatusScreen(),
          desktop: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const SystemStatusScreen(embedded: true),
            ),
          ),
          desktopTitle: 'System Status',
        )),
      ),
      GoRoute(
        path: '/admin/users',
        pageBuilder: (context, state) => _slideUpPage(const ResponsiveScreen(
          mobile: UsersScreen(),
          desktop: DesktopUsersScreen(),
          desktopTitle: 'Users',
        )),
      ),
      GoRoute(
        path: '/admin/users/new',
        pageBuilder: (context, state) => _slideUpPage(ResponsiveScreen(
          mobile: const AddUserScreen(),
          desktop: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const AddUserScreen(embedded: true),
            ),
          ),
          desktopTitle: 'Add User',
        )),
      ),
    ],
  );
});
