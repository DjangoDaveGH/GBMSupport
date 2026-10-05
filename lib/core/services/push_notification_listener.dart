import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/routing/app_router.dart';
import 'package:hyport/core/services/app_badge_service.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/core/services/local_notification_service.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/notifications/data/notification_providers.dart';

/// Wraps the app: once a user is signed in, requests notification
/// permission, registers this device's FCM token against their profile,
/// and wires up foreground/tap handling. Mirrors OfflineSyncListener's
/// shape — a thin ConsumerStatefulWidget sitting above MaterialApp.router
/// with no UI of its own.
class PushNotificationListener extends ConsumerStatefulWidget {
  final Widget child;

  const PushNotificationListener({super.key, required this.child});

  @override
  ConsumerState<PushNotificationListener> createState() => _PushNotificationListenerState();
}

class _PushNotificationListenerState extends ConsumerState<PushNotificationListener> {
  bool _started = false;
  final List<StreamSubscription<void>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _start() async {
    if (_started) return;
    final user = ref.read(currentAppUserProvider).valueOrNull;
    if (user == null) return;
    _started = true;

    LocalNotificationService.onTicketTap = (ticketId) {
      ref.read(routerProvider).push('/tickets/$ticketId');
      _markTicketNotificationsRead(ticketId);
    };

    final service = ref.read(pushNotificationServiceProvider);
    final granted = await service.requestPermission();
    if (!granted) return;

    final token = await service.getToken();
    if (token != null) {
      await ref.read(userRepositoryProvider).addFcmToken(user.id, token);
    }

    _subscriptions.add(service.onTokenRefresh.listen((newToken) {
      final current = ref.read(currentAppUserProvider).valueOrNull;
      if (current != null) {
        ref.read(userRepositoryProvider).addFcmToken(current.id, newToken);
      }
    }));

    _subscriptions.add(service.onForegroundMessage.listen((message) async {
      final text = message.notification?.body ?? message.data['message'] as String?;
      if (text == null) return;
      final unread = int.tryParse(message.data['unreadCount']?.toString() ?? '');
      // Firebase never auto-shows a system notification for a foreground
      // message (only background/terminated) — without this it was audible
      // and visible nowhere except an in-app SnackBar, easy to miss and
      // impossible to hear. Real tray/banner pop-up + sound instead, same
      // as what a background push already gets.
      try {
        await LocalNotificationService.show(
          title: message.notification?.title ?? 'Hyperion Support',
          body: text,
          ticketId: message.data['ticketId']?.toString(),
          badgeCount: unread,
        );
      } catch (error, stackTrace) {
        debugPrint('Could not display foreground notification: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (unread != null) AppBadgeService.set(unread);
    }));

    _subscriptions.add(service.onMessageOpenedApp.listen(_openTicketFrom));
    final initial = await service.initialMessage;
    if (initial != null) _openTicketFrom(initial);
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  void _openTicketFrom(RemoteMessage message) {
    final ticketId = message.data['ticketId'] as String?;
    if (ticketId != null && ticketId.isNotEmpty) {
      ref.read(routerProvider).push('/tickets/$ticketId');
      _markTicketNotificationsRead(ticketId);
    }
  }

  // Flips `read` on every unread notification about [ticketId] once the
  // user has actually opened it from a tap — keeps the app-icon badge (see
  // build()'s unreadNotificationCountProvider listener) from staying
  // inflated for someone who only ever taps the tray notification and
  // never visits the in-app Notifications list.
  void _markTicketNotificationsRead(String ticketId) {
    final userId = ref.read(currentAppUserProvider).valueOrNull?.id;
    if (userId == null) return;
    ref.read(notificationRepositoryProvider).markReadForTicket(userId, ticketId);
  }

  @override
  Widget build(BuildContext context) {
    // Re-attempt whenever sign-in state changes — _started only guards
    // against double-registering within the same signed-in session,
    // not across sign-out/sign-in (a second user on the same device
    // needs their own token registered too).
    ref.listen(currentAppUserProvider, (previous, next) {
      if (previous?.valueOrNull?.id != next.valueOrNull?.id) {
        _cancelSubscriptions();
        _started = false;
        _start();
        if (next.valueOrNull == null) AppBadgeService.set(0);
      }
    });

    // Keep the app-icon badge in step with the unread notification count
    // while the app is open (background pushes update it from the service
    // worker / aps.badge — see functions/index.js and firebase-messaging-sw.js).
    final userId = ref.watch(currentAppUserProvider).valueOrNull?.id;
    if (userId != null) {
      AppBadgeService.set(
        ref.read(unreadNotificationCountProvider(userId)).valueOrNull ?? 0,
      );
      ref.listen(unreadNotificationCountProvider(userId), (previous, next) {
        AppBadgeService.set(next.valueOrNull ?? 0);
      });
    }

    return widget.child;
  }
}
