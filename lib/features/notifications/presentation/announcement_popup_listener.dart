import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/routing/app_router.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/notifications/data/notification_providers.dart';
import 'package:hyport/features/notifications/domain/app_notification.dart';
import 'package:hyport/features/tickets/presentation/ticket_attachments_section.dart';
import 'package:intl/intl.dart';

/// Unread admin announcements for [userId], oldest first so they're shown
/// in the order they were sent.
final unreadAnnouncementsProvider = StreamProvider.autoDispose
    .family<List<AppNotification>, String>((ref, userId) {
      return ref
          .watch(notificationRepositoryProvider)
          .watchUnreadAnnouncements(userId);
    });

/// Routes where an announcement must not pop up: the splash, sign-in and
/// guest flows. Anywhere else counts as "in the app".
const _noPopupPrefixes = [
  '/splash',
  '/welcome',
  '/support/',
  '/guest/',
  '/login',
  '/phone-password-recovery',
  '/request-access',
];

/// Pops up every unread admin announcement when a signed-in user opens the
/// app, one at a time. Closing one marks its notification read, so it never
/// pops up again (and the Notifications badge comes down with it). Sits
/// above MaterialApp.router like the other listeners and shows its dialog
/// on the router's navigator.
class AnnouncementPopupListener extends ConsumerStatefulWidget {
  final Widget child;

  const AnnouncementPopupListener({super.key, required this.child});

  @override
  ConsumerState<AnnouncementPopupListener> createState() =>
      _AnnouncementPopupListenerState();
}

class _AnnouncementPopupListenerState
    extends ConsumerState<AnnouncementPopupListener> {
  /// Shown (or showing) this session, so a stream re-emit can't open the
  /// same one twice before its read flag lands.
  final _shown = <String>{};
  List<AppNotification> _pending = const [];
  bool _showing = false;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    _router = ref.read(routerProvider);
    _router!.routerDelegate.addListener(_maybeShow);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_maybeShow);
    super.dispose();
  }

  bool get _onAppScreen {
    final path = _router?.routerDelegate.currentConfiguration.uri.path ?? '';
    if (path.isEmpty || path == '/') return false;
    return !_noPopupPrefixes.any(path.startsWith);
  }

  void _maybeShow() {
    if (_showing || !mounted || !_onAppScreen) return;
    final next = _pending.where((n) => !_shown.contains(n.id)).firstOrNull;
    if (next == null) return;
    final navContext = _router?.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) return;

    _showing = true;
    _shown.add(next.id);
    final remaining =
        _pending.where((n) => !_shown.contains(n.id)).length;
    unawaited(
      showDialog<void>(
        context: navContext,
        barrierDismissible: false,
        builder: (_) => AnnouncementDialog(
          notification: next,
          remaining: remaining,
        ),
      ).whenComplete(() async {
        try {
          await ref.read(notificationRepositoryProvider).markRead(next.id);
        } catch (_) {
          // Offline or signed out mid-dialog: it'll pop up again next time.
        }
        _showing = false;
        if (mounted) {
          // Let the dialog's route finish closing before opening the next.
          Future.microtask(_maybeShow);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentAppUserProvider).valueOrNull?.id;
    if (uid != null) {
      _pending =
          ref.watch(unreadAnnouncementsProvider(uid)).valueOrNull ?? const [];
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
    } else {
      _pending = const [];
      _shown.clear();
    }
    return widget.child;
  }
}

class AnnouncementDialog extends StatelessWidget {
  final AppNotification notification;

  /// How many more unread announcements follow this one.
  final int remaining;

  const AnnouncementDialog({
    super.key,
    required this.notification,
    this.remaining = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = notification;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.campaign_rounded, color: AppTheme.accentBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title?.isNotEmpty == true ? n.title! : 'Announcement',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat.yMMMd().add_jm().format(n.createdAt)}'
                  '${n.edited ? ' · Edited' : ''}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(n.message, style: theme.textTheme.bodyMedium),
              if (n.attachmentUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                TicketAttachmentsSection(attachmentUrls: n.attachmentUrls),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(remaining > 0 ? 'Next ($remaining more)' : 'Close'),
        ),
      ],
    );
  }
}
