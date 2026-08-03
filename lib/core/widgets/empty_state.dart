import 'package:flutter/material.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// Icon-on-blob composition — layered soft circles behind a white icon
/// disc, echoing the reference illustration set's pattern (e.g. the bank
/// building with an orange plus badge, the shield with a green check
/// badge) using only vector shapes, no image assets.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color? tint;
  final IconData? badgeIcon;
  final Color? badgeColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.tint,
    this.badgeIcon,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final blob = tint ?? AppTheme.accentBlue;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 4,
                    right: -4,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(color: blob.withValues(alpha: 0.12), shape: BoxShape.circle),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha: 0.10), shape: BoxShape.circle),
                    ),
                  ),
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: softShadow(opacity: 0.08),
                    ),
                    child: Icon(icon, size: 32, color: blob),
                  ),
                  if (badgeIcon != null)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: badgeColor ?? AppTheme.gold,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(badgeIcon, size: 13, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
