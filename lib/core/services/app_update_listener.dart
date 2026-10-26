import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hyport/core/services/global_keys.dart';
import 'package:hyport/core/services/web_update.dart';

/// Checks whether the hosted web build is newer than the build currently
/// running. The prompt is deliberately non-blocking so it cannot interrupt a
/// user while they are completing a ticket.
class AppUpdateListener extends StatefulWidget {
  final Widget child;

  const AppUpdateListener({super.key, required this.child});

  @override
  State<AppUpdateListener> createState() => _AppUpdateListenerState();
}

class _AppUpdateListenerState extends State<AppUpdateListener>
    with WidgetsBindingObserver {
  // Keep this in sync with pubspec.yaml's version. Each web deployment must
  // increment the build number so an already-running app can detect it.
  static const _runningBuild = '1.0.11+15';
  static const _checkInterval = Duration(minutes: 10);

  Timer? _timer;
  bool _promptShown = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      // Allow the first Flutter frame to render before making a network check.
      unawaited(Future<void>.delayed(const Duration(seconds: 2), _check));
      _timer = Timer.periodic(_checkInterval, (_) => _check());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (!kIsWeb || _checking || _promptShown) return;
    _checking = true;
    try {
      final response = await http
          .get(
            Uri.parse(
              '/version.json?update_check=${DateTime.now().millisecondsSinceEpoch}',
            ),
            headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return;
      final deployedBuild =
          '${data['version'] ?? ''}+${data['build_number'] ?? ''}';
      if (deployedBuild.isNotEmpty &&
          deployedBuild != _runningBuild &&
          mounted) {
        _promptShown = true;
        _showUpdatePrompt();
      }
    } catch (error) {
      debugPrint('App update check failed: $error');
    } finally {
      _checking = false;
    }
  }

  void _showUpdatePrompt() {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) {
      _promptShown = false;
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        behavior: SnackBarBehavior.floating,
        content: const Text(
          'A new version is available. Tap “Refresh now” to update the app.',
        ),
        action: SnackBarAction(
          label: 'Refresh now',
          onPressed: () => unawaited(reloadWebApp()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
