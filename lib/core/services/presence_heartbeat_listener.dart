import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';

/// Wraps the app; while a user is signed in and the app is in the
/// foreground, periodically touches users/{uid}.lastActiveAt so
/// AppUser.isRecentlyActive (the online/offline dot on the admin Users list
/// and the ticket chat header) reflects the user's *current* session
/// instead of going stale ~5 minutes after their last sign-in — see
/// UserRepository.touchLastActive, which used to only ever be called once,
/// from app_router.dart's auth-state-change listener.
class PresenceHeartbeatListener extends ConsumerStatefulWidget {
  final Widget child;

  const PresenceHeartbeatListener({super.key, required this.child});

  @override
  ConsumerState<PresenceHeartbeatListener> createState() => _PresenceHeartbeatListenerState();
}

class _PresenceHeartbeatListenerState extends ConsumerState<PresenceHeartbeatListener>
    with WidgetsBindingObserver {
  Timer? _timer;

  // Comfortably inside AppUser.isRecentlyActive's 5-minute window, so an
  // open session never has a chance to read as offline between beats.
  static const _interval = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startIfSignedIn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back to the app shouldn't wait up to 2 minutes for the dot
      // to catch up.
      _touch();
      _startIfSignedIn();
    } else {
      // Backgrounded/inactive: no point ticking for a session that isn't
      // actually being used right now — it'll simply age past 5 minutes
      // and read as offline, which is correct.
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startIfSignedIn() {
    if (_timer != null) return;
    final uid = ref.read(authStateChangesProvider).valueOrNull?.uid;
    if (uid == null) return;
    _touch();
    _timer = Timer.periodic(_interval, (_) => _touch());
  }

  void _touch() {
    final uid = ref.read(authStateChangesProvider).valueOrNull?.uid;
    if (uid != null) {
      ref.read(userRepositoryProvider).touchLastActive(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateChangesProvider, (previous, next) {
      if (next.valueOrNull != null) {
        _startIfSignedIn();
      } else {
        _timer?.cancel();
        _timer = null;
      }
    });
    return widget.child;
  }
}
