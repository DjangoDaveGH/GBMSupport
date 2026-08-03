import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// A rotating gradient-ring spinner (navy -> accent blue), replacing the
/// default Material CircularProgressIndicator everywhere in the app so
/// loading states carry the same brand identity as everything else,
/// matching the reference "LOADING…" graphic's conic-ring composition.
class BrandedLoader extends StatefulWidget {
  final double size;
  final String? label;

  const BrandedLoader({super.key, this.size = 36, this.label});

  @override
  State<BrandedLoader> createState() => _BrandedLoaderState();
}

class _BrandedLoaderState extends State<BrandedLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = RotationTransition(
      turns: _controller,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: _RingPainter()),
      ),
    );

    if (widget.label == null) return ring;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ring,
        const SizedBox(height: 12),
        Text(
          widget.label!.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
              ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.width * 0.12;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [
          Colors.transparent,
          AppTheme.accentBlue,
          AppTheme.navy,
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect.deflate(strokeWidth / 2), 0, math.pi * 2 * 0.85, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Drop-in replacement for `Center(child: CircularProgressIndicator())`.
class BrandedLoaderCenter extends StatelessWidget {
  final double size;

  const BrandedLoaderCenter({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) => Center(child: BrandedLoader(size: size));
}
