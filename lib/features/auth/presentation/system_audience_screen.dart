import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// The approved GHANEPS/GIFMIS journey branches at this screen: government
/// users sign into their institutional account; public users continue as
/// guests.
class SystemAudienceScreen extends StatelessWidget {
  final String product;

  const SystemAudienceScreen({super.key, required this.product});

  String get _system =>
      product.toLowerCase() == 'gifmis' ? 'gifmis' : 'ghaneps';
  String get _title => _system.toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.go('/welcome'),
          icon: const Icon(Icons.chevron_left_rounded, size: 34),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    Image.asset(
                      'assets/images/mof_logo.png',
                      width: 148,
                      height: 148,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'MINISTRY FOR FINANCE\nREPUBLIC OF GHANA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.7,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(flex: 3),
                    Text(
                      '$_title SUPPORT',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: AppTheme.navy,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                    ),
                    const SizedBox(height: 36),
                    Row(
                      children: [
                        Expanded(
                          child: _AudienceButton(
                            label: 'GOVERNMENT',
                            onPressed: () =>
                                context.go('/login?system=$_system'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _AudienceButton(
                            label: 'PUBLIC',
                            onPressed: () => context.go('/guest/$_system'),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(flex: 4),
                    if (_system == 'ghaneps')
                      Image.asset(
                        'assets/images/ghaneps_logo.png',
                        width: 152,
                        height: 46,
                        fit: BoxFit.contain,
                      )
                    else
                      Text(
                        'GIFMIS',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.navy,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AudienceButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AudienceButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    ),
  );
}
