import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/audit_log.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/core/widgets/percent_ring.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/dashboard/data/audit_log_providers.dart';
import 'package:hyport/features/dashboard/domain/audit_log_formatting.dart';
import 'package:hyport/features/knowledge_base/data/knowledge_base_providers.dart';
import 'package:hyport/features/notifications/data/notification_providers.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart'
    show categoryIcon;
import 'package:intl/intl.dart';
import 'package:hyport/core/widgets/branded_loader.dart';

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good Morning';
  if (hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.MMMd().format(dt);
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final isSupportSide = appUser?.role.isSupportSide ?? false;

    return Scaffold(
      backgroundColor: AppTheme.mist,
      drawer: isSupportSide ? _AdminDrawer(appUser: appUser!) : null,
      body: appUser == null
          ? const BrandedLoaderCenter()
          : SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _HomeHeader(appUser: appUser, showMenu: isSupportSide),
                  Expanded(
                    child: isSupportSide
                        ? _SupportHome(appUser: appUser)
                        : _UserHome(appUser: appUser),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HomeHeader extends ConsumerWidget {
  final AppUser appUser;
  final bool showMenu;

  const _HomeHeader({required this.appUser, this.showMenu = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider(appUser.id));
    final institutions = ref.watch(institutionListProvider).valueOrNull ?? const [];
    final institutionName = [
      for (final i in institutions)
        if (i.id == appUser.institutionId) i.name,
    ].firstOrNull ?? appUser.institutionType.wireValue;

    return Material(
      color: Colors.white,
      child: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: SizedBox.shrink())),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMenu)
                  Builder(
                    builder: (context) => Padding(
                      padding: const EdgeInsets.only(right: 12, top: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        onTap: () => Scaffold.of(context).openDrawer(),
                        child: const Icon(
                          Icons.menu_rounded,
                          color: AppTheme.navy,
                          size: 23,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
                    child: Text(
                      appUser.name.isEmpty
                          ? '?'
                          : appUser.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()}, 👋',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: AppTheme.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        appUser.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: AppTheme.ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        showMenu ? appUser.role.label : institutionName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.push('/notifications'),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.notifications_none_rounded,
                            color: AppTheme.navy,
                            size: 22,
                          ),
                          if (unread > 0)
                            Positioned(
                              right: -3,
                              top: -3,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: StatusColors.critical,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 9,
                                  minHeight: 9,
                                ),
                              ),
                            ),
                        ],
                      ),
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

/// Navigation for everything that isn't one of the 4 primary bottom-nav
/// destinations (Phase 4 mockup screen 19's ☰ icon) — Analytics, Reports,
/// Knowledge Base, and (PFM Management only) Users/Institutions/Settings.
class _AdminDrawer extends StatelessWidget {
  final AppUser appUser;

  const _AdminDrawer({required this.appUser});

  @override
  Widget build(BuildContext context) {
    final isPfmManagement = appUser.role == UserRole.pfmManagement;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GBMS',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: AppTheme.gold),
                  ),
                  Text(
                    'Support Centre',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _drawerTile(
              context,
              Icons.bar_chart_rounded,
              'Analytics',
              () => context.push('/analytics'),
            ),
            _drawerTile(
              context,
              Icons.description_outlined,
              'Reports',
              () => context.push('/reports'),
            ),
            _drawerTile(
              context,
              Icons.menu_book_outlined,
              'Knowledge Base',
              () => context.push('/knowledge-base'),
            ),
            if (isPfmManagement) ...[
              const Divider(height: 1),
              _drawerTile(
                context,
                Icons.people_outline_rounded,
                'Users',
                () => context.push('/admin/users'),
              ),
              _drawerTile(
                context,
                Icons.account_balance_outlined,
                'Institutions',
                () => context.push('/admin/institutions'),
              ),
              _drawerTile(
                context,
                Icons.settings_outlined,
                'Settings',
                () => context.push('/admin-settings'),
              ),
            ],
            const Spacer(),
            const Divider(height: 1),
            _drawerTile(
              context,
              Icons.person_outline_rounded,
              'Profile',
              () => context.go('/profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.accentBlue),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;

  const _SectionHeader({required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (onViewAll != null)
          TextButton(onPressed: onViewAll, child: const Text('View all')),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push('/system-status'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All systems operational',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      'System Status',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: AppTheme.success),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.success,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatNumberCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatNumberCard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: softShadow(),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _QuickActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: Icon(icon, color: fg, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showContactSupportSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.plum.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: AppTheme.plum,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Need help fast?',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Log a support ticket and the PFM-Systems team will respond, or browse the Knowledge Base for instant answers to common GBMS issues.',
              style: Theme.of(
                sheetContext,
              ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/tickets/new');
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create a Ticket'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/knowledge-base');
                },
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('Browse Knowledge Base'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _UserHome extends ConsumerWidget {
  final AppUser appUser;

  const _UserHome({required this.appUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(
      ticketListProvider((appUser, const TicketFilter())),
    );

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load tickets: $e')),
      data: (tickets) {
        final openCount = tickets
            .where((t) => t.status == TicketStatus.open)
            .length;
        final pendingCount = tickets
            .where(
              (t) => {
                TicketStatus.assigned,
                TicketStatus.inProgress,
                TicketStatus.escalated,
                TicketStatus.reopened,
              }.contains(t.status),
            )
            .length;
        final resolvedCount = tickets
            .where(
              (t) => {
                TicketStatus.resolved,
                TicketStatus.closed,
              }.contains(t.status),
            )
            .length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const _StatusBanner(),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _StatNumberCard(
                    value: '$openCount',
                    label: 'Open Tickets',
                    color: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatNumberCard(
                    value: '$pendingCount',
                    label: 'Pending',
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatNumberCard(
                    value: '$resolvedCount',
                    label: 'Resolved',
                    color: AppTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _QuickActionItem(
                  icon: Icons.add_rounded,
                  label: 'Create Ticket',
                  bg: AppTheme.navy,
                  fg: Colors.white,
                  onTap: () => context.push('/tickets/new'),
                ),
                const SizedBox(width: 10),
                _QuickActionItem(
                  icon: Icons.confirmation_number_outlined,
                  label: 'My Tickets',
                  bg: AppTheme.accentBlue.withValues(alpha: 0.12),
                  fg: AppTheme.accentBlue,
                  onTap: () => context.push('/tickets'),
                ),
                const SizedBox(width: 10),
                _QuickActionItem(
                  icon: Icons.menu_book_rounded,
                  label: 'Knowledge Base',
                  bg: AppTheme.gold.withValues(alpha: 0.16),
                  fg: AppTheme.gold,
                  onTap: () => context.push('/knowledge-base'),
                ),
                const SizedBox(width: 10),
                _QuickActionItem(
                  icon: Icons.support_agent_rounded,
                  label: 'Contact Support',
                  bg: AppTheme.plum.withValues(alpha: 0.12),
                  fg: AppTheme.plum,
                  onTap: () => _showContactSupportSheet(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              title: 'Recent Tickets',
              onViewAll: () => context.push('/tickets'),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (tickets.isEmpty)
              const EmptyState(
                icon: Icons.task_alt_rounded,
                message: 'No open tickets right now.',
              )
            else
              ...tickets.take(5).map((t) => _HomeTicketTile(ticket: t)),
          ],
        );
      },
    );
  }
}

/// Phase 4 mockup screen 19 — Admin Dashboard. Every KPI is a real,
/// currently-true count; the four backlog-state tiles (Open/In Progress/
/// Overdue/Escalated) deliberately don't show a fabricated %-change since
/// there's no stored daily history to compare against — only Total and
/// Resolved (genuine flow metrics) get a real week-over-week comparison,
/// same math as AnalyticsScreen.
class _SupportHome extends ConsumerWidget {
  final AppUser appUser;

  const _SupportHome({required this.appUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(
      ticketListProvider((appUser, const TicketFilter())),
    );
    final slaPolicy =
        ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();
    // users/{uid} and audit_logs are unreadable by Vendor per
    // firestore.rules' isSupportSide() (deliberately excludes Vendor —
    // Section 3 caps them at "resolve or re-escalate"), and this widget is
    // shared with Vendor via HomeScreen's broader isSupportSide check — so
    // these two watches are skipped entirely for Vendor rather than
    // issuing a doomed-to-permission-denied read. institutions and
    // knowledge_articles are readable by anyone signed in, so those stay
    // unconditional.
    final hasBackOfficeAccess = appUser.role.hasBackOfficeAccess;
    final allUsers = hasBackOfficeAccess ? ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[] : const <AppUser>[];
    final activeUserCount = allUsers.where((u) => u.isActive).length;
    final institutionCount = ref.watch(institutionListProvider).valueOrNull?.length ?? 0;
    final articleCount = ref.watch(articleListProvider(null)).valueOrNull?.length ?? 0;
    final recentAdminActions = hasBackOfficeAccess
        ? ref.watch(adminActionsAuditLogProvider).valueOrNull?.take(5).toList() ?? const <AuditLog>[]
        : const <AuditLog>[];
    final usersById = <String, AppUser>{for (final u in allUsers) u.id: u};

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load tickets: $e')),
      data: (tickets) {
        final open = tickets.where((t) => t.status == TicketStatus.open).length;
        final resolved = tickets
            .where(
              (t) => {
                TicketStatus.resolved,
                TicketStatus.closed,
              }.contains(t.status),
            )
            .length;
        final inProgress = tickets
            .where((t) => t.status == TicketStatus.inProgress)
            .length;
        final escalated = tickets
            .where((t) => t.status == TicketStatus.escalated)
            .length;
        final overdue = SlaCalculator.countOverdue(tickets, slaPolicy);
        final myAssigned = tickets
            .where((t) => t.assignedTo == appUser.id && t.status.isOpenState)
            .length;
        final slaCompliance = SlaCalculator.complianceRate(tickets, slaPolicy);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 15,
                  color: AppTheme.accentBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  'Today, ${DateFormat.yMMMd().format(DateTime.now())}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                _StatNumberCard(
                  value: '${tickets.length}',
                  label: 'Total Tickets',
                  color: AppTheme.navy,
                ),
                _StatNumberCard(
                  value: '$open',
                  label: 'Open',
                  color: AppTheme.accentBlue,
                ),
                _StatNumberCard(
                  value: '$resolved',
                  label: 'Resolved',
                  color: StatusColors.resolved,
                ),
                _StatNumberCard(
                  value: '$inProgress',
                  label: 'In Progress',
                  color: AppTheme.gold,
                ),
                _StatNumberCard(
                  value: '$overdue',
                  label: 'Overdue',
                  color: StatusColors.critical,
                ),
                _StatNumberCard(
                  value: '$escalated',
                  label: 'Escalated',
                  color: StatusColors.escalated,
                ),
              ],
            ),
            // Users/institutions/audit_logs are unreadable by Vendor per
            // firestore.rules' isSupportSide() (deliberately excludes
            // Vendor — Section 3 caps them at "resolve or re-escalate");
            // this ListView is shared with Vendor via HomeScreen's broader
            // isSupportSide check, so these two sections are scoped to the
            // narrower hasBackOfficeAccess to match what Vendor can
            // actually read, rather than showing them a wrong "0".
            if (appUser.role.hasBackOfficeAccess) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('System Overview', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [
                  _StatNumberCard(
                    value: '$activeUserCount',
                    label: 'Active Users',
                    color: AppTheme.navy,
                  ),
                  _StatNumberCard(
                    value: '$institutionCount',
                    label: 'Institutions',
                    color: AppTheme.accentBlue,
                  ),
                  _StatNumberCard(
                    value: '$articleCount',
                    label: 'KB Articles',
                    color: AppTheme.gold,
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                boxShadow: softShadow(),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$myAssigned',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: AppTheme.navy),
                        ),
                        Text(
                          'My Assigned',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'SLA Compliance',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 10),
                  PercentRing(
                    percent: slaCompliance,
                    color: StatusColors.resolved,
                    size: 52,
                    strokeWidth: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              title: 'Recent Tickets',
              onViewAll: () => context.push('/tickets'),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (tickets.isEmpty)
              const EmptyState(
                icon: Icons.inbox_outlined,
                message: 'No tickets have come in yet.',
              )
            else
              ...tickets.take(10).map((t) => _HomeTicketTile(ticket: t)),
            if (appUser.role.hasBackOfficeAccess) ...[
              const SizedBox(height: AppSpacing.xl),
              _SectionHeader(
                title: 'Recent System Activity',
                onViewAll: () => context.push('/audit-logs'),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (recentAdminActions.isEmpty)
                const EmptyState(
                  icon: Icons.history_rounded,
                  message: 'No admin activity recorded yet.',
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < recentAdminActions.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _ActivityTile(entry: recentAdminActions[i], usersById: usersById),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final AuditLog entry;
  final Map<String, AppUser> usersById;

  const _ActivityTile({required this.entry, required this.usersById});

  @override
  Widget build(BuildContext context) {
    final actor = usersById[entry.actorId]?.name ?? 'System';
    final target = usersById[entry.targetId]?.name ?? entry.targetId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: Theme.of(context).textTheme.bodySmall,
                children: [
                  TextSpan(text: actor, style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' ${adminActionLabel(entry.action).toLowerCase()} '),
                  TextSpan(text: target, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          Text(DateFormat.MMMd().format(entry.timestamp), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HomeTicketTile extends StatelessWidget {
  final Ticket ticket;

  const _HomeTicketTile({required this.ticket});

  Color get _priorityColor => switch (ticket.priority) {
    TicketPriority.critical => StatusColors.critical,
    TicketPriority.high => StatusColors.high,
    TicketPriority.medium => StatusColors.medium,
    TicketPriority.low => StatusColors.low,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.push('/tickets/${ticket.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    categoryIcon(ticket.category),
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
                        ticket.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '#${ticket.ticketReference}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            ticket.priority.label,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: _priorityColor),
                          ),
                          Text(
                            '  ·  ${_relativeTime(ticket.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
