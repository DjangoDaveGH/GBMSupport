import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:hyport/core/services/pwa_install.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// "Install app" affordance for the web build — shown to every web visitor
/// who hasn't already installed it (hidden entirely on mobile/non-web,
/// where PwaInstall.isSupported is false). Chrome/Edge get the real native
/// `beforeinstallprompt` flow; every other browser (Safari has no such
/// event at all, and Chrome doesn't always fire it immediately) still gets
/// the button, tapping it just shows manual "Add to Home Screen" steps
/// instead of silently doing nothing or never appearing.
class PwaInstallButton extends StatefulWidget {
  /// Compact = a bare icon button (for a top bar). Otherwise a small
  /// labeled pill, meant to float over shell chrome that has no top bar.
  final bool compact;

  const PwaInstallButton({super.key, this.compact = false});

  @override
  State<PwaInstallButton> createState() => _PwaInstallButtonState();
}

class _PwaInstallButtonState extends State<PwaInstallButton> {
  bool _installed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && PwaInstall.isSupported) {
      _installed = PwaInstall.isInstalled;
      // Installed state can flip mid-session (native prompt accepted, or —
      // on Chrome — the user installs via the browser's own omnibox
      // control rather than this button) — same imperceptible 1s poll the
      // old canInstall-watching version used, just watching a different
      // flag now that visibility no longer depends on canInstall.
      _poll = Timer.periodic(const Duration(seconds: 1), (_) {
        final installed = PwaInstall.isInstalled;
        if (installed != _installed && mounted) setState(() => _installed = installed);
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (PwaInstall.canInstall) {
      final outcome = await PwaInstall.promptInstall();
      if (mounted && outcome == 'accepted') setState(() => _installed = true);
      return;
    }
    if (mounted) _showManualInstructions();
  }

  void _showManualInstructions() {
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Install App'),
        content: Text(
          isIOS
              ? 'Tap the Share icon in your browser\'s toolbar, then choose "Add to Home Screen".'
              : 'Open your browser\'s menu and choose "Install app" or "Add to Home Screen".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !PwaInstall.isSupported || _installed) return const SizedBox.shrink();

    if (widget.compact) {
      return IconButton(
        icon: const Icon(Icons.install_mobile_rounded),
        tooltip: 'Install app',
        color: AppTheme.navy,
        onPressed: _handleTap,
      );
    }

    return Material(
      color: AppTheme.navy,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: _handleTap,
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
