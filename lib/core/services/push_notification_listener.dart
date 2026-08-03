import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/routing/app_router.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/core/services/global_keys.dart';
import 'package:hyport/features/auth/data/user_providers.dart';

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

  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  Future<void> _start() async {
    if (_started) return;
    final user = ref.read(currentAppUserProvider).valueOrNull;
    if (user == null) return;
    _started = true;

    final service = ref.read(pushNotificationServiceProvider);
    final granted = await service.requestPermission();
    if (!granted) return;

    final token = await service.getToken();
    if (token != null) {
      await ref.read(userRepositoryProvider).addFcmToken(user.id, token);
    }

    service.onTokenRefresh.listen((newToken) {
      final current = ref.read(currentAppUserProvider).valueOrNull;
      if (current != null) {
        ref.read(userRepositoryProvider).addFcmToken(current.id, newToken);
      }
    });

    service.onForegroundMessage.listen((message) {
      final text = message.notification?.body ?? message.data['message'] as String?;
      if (text != null) {
        scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
      }
    });

    service.onMessageOpenedApp.listen(_openTicketFrom);
    final initial = await service.initialMessage;
    if (initial != null) _openTicketFrom(initial);
  }

  void _openTicketFrom(RemoteMessage message) {
    final ticketId = message.data['ticketId'] as String?;
    if (ticketId != null && ticketId.isNotEmpty) {
      ref.read(routerProvider).push('/tickets/$ticketId');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-attempt whenever sign-in state changes — _started only guards
    // against double-registering within the same signed-in session,
    // not across sign-out/sign-in (a second user on the same device
    // needs their own token registered too).
    ref.listen(currentAppUserProvider, (previous, next) {
      if (previous?.valueOrNull?.id != next.valueOrNull?.id) {
        _started = false;
        _start();
      }
    });
    return widget.child;
  }
}
