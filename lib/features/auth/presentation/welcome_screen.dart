import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// Mockup screen 2 — sits between Splash and Login, reachable only while
/// signed out (see app_router.dart's redirect logic). Was missing entirely
/// before this pass; the app went straight from Splash to Login.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Image.asset(
                    'assets/images/illustration_agent.png',
                    width: 240,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Welcome to GBMS\nSupport Centre',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We are here to help you. Report issues, track your tickets and get the support you need.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _FeatureRow(
                    icon: Icons.confirmation_number_outlined,
                    title: 'Report Issues',
                    description: 'Easily create and submit support tickets.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FeatureRow(
                    icon: Icons.trending_up_rounded,
                    title: 'Track Progress',
                    description:
                        'Monitor the status of your tickets in real-time.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FeatureRow(
                    icon: Icons.task_alt_rounded,
                    title: 'Get Resolutions',
                    description:
                        'Receive timely support and updates from our team.',
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const SizedBox(
                      width: double.infinity,
                      child: Text('GET STARTED', textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: 20, color: AppTheme.accentBlue),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
