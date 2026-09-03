import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/notifications/data/notification_providers.dart';
import 'package:hyport/features/notifications/data/notification_repository.dart';
import 'package:hyport/features/notifications/domain/app_notification.dart';
import 'package:intl/intl.dart';
import 'package:hyport/core/widgets/branded_loader.dart';

IconData _iconFor(NotificationType type) => switch (type) {
      NotificationType.ticketReceived => Icons.inbox_rounded,
      NotificationType.assigned => Icons.person_add_alt_rounded,
      NotificationType.escalated => Icons.arrow_upward_rounded,
      NotificationType.pendingAction => Icons.hourglass_top_rounded,
      NotificationType.resolved => Icons.check_circle_outline_rounded,
      NotificationType.systemDowntime => Icons.power_off_rounded,
      NotificationType.deadlineReminder => Icons.event_available_rounded,
      NotificationType.maintenance => Icons.build_rounded,
      NotificationType.chatMessage => Icons.chat_bubble_outline_rounded,
    };

// Mockup screen 7 groups notifications into All/Tickets/System/
// Announcements tabs, but the data model (NotificationType) predates that
// split and has no explicit "announcement" vs "system" distinction — it's
// all ticket-lifecycle events plus two ops-style types. Mapped by closest
// fit: ticket-lifecycle events under Tickets; an outage/downtime alert is
// the "something is currently wrong" System case; scheduled maintenance
// reads as the "heads up, this is planned" Announcements case in the
// mockup's own example ("Announcement: System maintenance on May 25...").
bool _isTicketNotification(NotificationType type) => switch (type) {
      NotificationType.ticketReceived ||
      NotificationType.assigned ||
      NotificationType.escalated ||
      NotificationType.pendingAction ||
      NotificationType.resolved ||
      NotificationType.deadlineReminder ||
      NotificationType.chatMessage => true,
      NotificationType.systemDowntime || NotificationType.maintenance => false,
    };

Color _colorFor(NotificationType type) => switch (type) {
      NotificationType.ticketReceived => AppTheme.accentBlue,
      NotificationType.assigned => StatusColors.assigned,
      NotificationType.escalated => StatusColors.critical,
      NotificationType.pendingAction => AppTheme.gold,
      NotificationType.resolved => StatusColors.resolved,
      NotificationType.systemDowntime => StatusColors.critical,
      NotificationType.deadlineReminder => AppTheme.gold,
      NotificationType.maintenance => AppTheme.accentBlue,
      NotificationType.chatMessage => AppTheme.accentBlue,
    };

String _dayLabel(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat.EEEE().format(dt);
  return DateFormat.yMMMd().format(dt);
}

/// Preserves the incoming (already-descending) order while bucketing by day
/// label, so within-day chronological order is untouched.
Map<String, List<AppNotification>> _groupByDay(List<AppNotification> notifications) {
  final grouped = <String, List<AppNotification>>{};
  for (final n in notifications) {
    grouped.putIfAbsent(_dayLabel(n.createdAt), () => []).add(n);
  }
  return grouped;
}

class NotificationsScreen extends StatefulWidget {
  /// When true, renders just the tab bar + list content with no Scaffold/
  /// AppBar of its own — for embedding inside DesktopShell (which already
  /// provides the title/top bar), so desktop web doesn't show this mobile
  /// screen's own app bar stacked underneath DesktopShell's. See
  /// core/responsive.dart's ResponsiveScreen usage in app_router.dart.
  final bool embedded;

  const NotificationsScreen({super.key, this.embedded = false});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final appUser = ref.watch(currentAppUserProvider).valueOrNull;
        if (appUser == null) return widget.embedded ? const BrandedLoaderCenter() : const Scaffold(body: BrandedLoaderCenter());

        final notificationsAsync = ref.watch(userNotificationsProvider(appUser.id));
        final repo = ref.read(notificationRepositoryProvider);

        final markAllRead = notificationsAsync.maybeWhen(
          data: (notifications) => notifications.any((n) => !n.read)
              ? TextButton(
                  onPressed: () => repo.markAllRead(
                    notifications.where((n) => !n.read).map((n) => n.id).toList(),
                  ),
                  child: const Text('Mark all read'),
                )
              : const SizedBox.shrink(),
          orElse: () => const SizedBox.shrink(),
        );

        final tabBar = TabBar(
          controller: _tabController,
          // 4 tabs (was 2) — "Announcements" doesn't fit a fixed-width
          // quarter-share of a 390px phone screen without wrapping/clipping,
          // so always scroll now rather than only when embedded.
          isScrollable: true,
          labelColor: AppTheme.navy,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: AppTheme.navy,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Tickets'),
            Tab(text: 'System'),
            Tab(text: 'Announcements'),
          ],
        );

        final body = notificationsAsync.when(
          loading: () => const BrandedLoaderCenter(),
          error: (e, _) => Center(child: Text('Could not load notifications: $e')),
          data: (notifications) => TabBarView(
            controller: _tabController,
            children: [
              _NotificationList(notifications: notifications, repo: repo),
              _NotificationList(
                notifications: notifications.where((n) => _isTicketNotification(n.type)).toList(),
                repo: repo,
              ),
              _NotificationList(
                notifications: notifications.where((n) => n.type == NotificationType.systemDowntime).toList(),
                repo: repo,
              ),
              _NotificationList(
                notifications: notifications.where((n) => n.type == NotificationType.maintenance).toList(),
                repo: repo,
              ),
            ],
          ),
        );

        if (widget.embedded) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: Align(alignment: Alignment.centerLeft, child: tabBar)),
                  markAllRead,
                ],
              ),
              const Divider(height: 1),
              Expanded(child: body),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [markAllRead, const SizedBox(width: 8)],
            bottom: tabBar,
          ),
          body: body,
        );
      },
    );
  }
}

class _NotificationList extends StatelessWidget {
  final List<AppNotification> notifications;
  final NotificationRepository repo;

  const _NotificationList({required this.notifications, required this.repo});

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return const EmptyState(icon: Icons.notifications_none_rounded, message: 'No notifications here.');
    }
    final grouped = _groupByDay(notifications);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              entry.key.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          ...entry.value.map((n) => _NotificationTile(
                notification: n,
                onTap: () {
                  if (!n.read) repo.markRead(n.id);
                  if (n.ticketId != null) context.push('/tickets/${n.ticketId}');
                },
              )),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(notification.type);
    final read = notification.read;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: read ? Colors.white : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: read ? Theme.of(context).colorScheme.outlineVariant : color.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: read ? 0.08 : 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(_iconFor(notification.type), size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (notification.title != null && notification.title!.isNotEmpty) ...[
                        Text(
                          notification.title!,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: read ? FontWeight.w600 : FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        notification.message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: read ? FontWeight.w400 : FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(DateFormat.jm().format(notification.createdAt), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (!read)
                  Container(
                    margin: const EdgeInsets.only(top: 4, left: 8),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
