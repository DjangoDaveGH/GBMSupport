import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/services/last_route_service.dart';

/// Shown for any location no route matches. Replaces go_router's default
/// error page, whose "Go to home page" button targets '/' — not a route
/// here, so it just landed back on the same error.
///
/// Also forgets the saved resume location: the redirect saves every location
/// that clears its guards, and an unmatched one does, so without this a
/// mistyped/stale URL would be reopened on every cold start.
class NotFoundScreen extends StatefulWidget {
  const NotFoundScreen({super.key});

  @override
  State<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _NotFoundScreenState extends State<NotFoundScreen> {
  @override
  void initState() {
    super.initState();
    LastRouteService.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off_rounded, size: 56, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('Page not found', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    "The page you're looking for doesn't exist or has moved.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Go to Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
