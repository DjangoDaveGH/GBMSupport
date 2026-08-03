import 'package:flutter/material.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/hex_pattern.dart';

/// Shown while the initial Firebase Auth state resolves (see
/// app_router.dart's redirect — it holds here until authStateChangesProvider
/// has emitted at least once, then moves on to /login or /home).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navyDarkest,
      body: HexPatternBackground(
        opacity: 0.05,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Image.asset(
                  'assets/images/mof_logo.png',
                  width: 84,
                  height: 84,
                ),
                const SizedBox(height: 16),
                const Text(
                  'MINISTRY OF FINANCE',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'REPUBLIC OF GHANA',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(flex: 1),
                const Text(
                  'ORACLE HYPERION\nSUPPORT CENTRE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    height: 1.3,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your trusted support partner for Oracle Hyperion solutions',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 42,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.gold,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const Spacer(flex: 2),
                const BrandedLoader(size: 32),
                const SizedBox(height: 24),
                Text(
                  'Powered by PFMSD Applications Unit',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11.5,
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
