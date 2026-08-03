import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hyport/core/services/pwa_install.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// "Install app" affordance for the web build — hidden entirely on
/// mobile/non-web (PwaInstall.isSupported is false there) and hidden on web
/// itself until the browser actually fires `beforeinstallprompt` (Chrome/
/// Edge only; no such event on Safari/Firefox, so those visitors never see
/// it rather than seeing a button that does nothing). Polls PwaInstall.
/// canInstall on a timer rather than a stream — the JS bridge is a plain
/// object, not an event emitter Dart can subscribe to, and a 1s poll is
/// imperceptible for a UI toggle that only flips once or twice per session.
class PwaInstallButton extends StatefulWidget {
  /// Compact = a bare icon button (for a top bar). Otherwise a small
  /// labeled pill, meant to float over shell chrome that has no top bar.
  final bool compact;

  const PwaInstallButton({super.key, this.compact = false});

  @override
  State<PwaInstallButton> createState() => _PwaInstallButtonState();
}

class _PwaInstallButtonState extends State<PwaInstallButton> {
  bool _visible = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && PwaInstall.isSupported) {
      _visible = PwaInstall.canInstall;
      _poll = Timer.periodic(const Duration(seconds: 1), (_) {
        final canInstall = PwaInstall.canInstall;
        if (canInstall != _visible && mounted) setState(() => _visible = canInstall);
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _install() async {
    final outcome = await PwaInstall.promptInstall();
    if (!mounted) return;
    if (outcome == 'accepted') setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_visible) return const SizedBox.shrink();

    if (widget.compact) {
      return IconButton(
        icon: const Icon(Icons.install_mobile_rounded),
        tooltip: 'Install app',
        color: AppTheme.navy,
        onPressed: _install,
      );
    }

    return Material(
      color: AppTheme.navy,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: _install,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.install_mobile_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                'Install App',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
