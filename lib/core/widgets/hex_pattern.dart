import 'package:flutter/material.dart';

/// The reference brand assets' dark geometric hex-link texture
/// (`assets/images/bg_hex_pattern.png`), shown faint behind content on a
/// dark (navy) surface — low opacity so it reads as texture, not
/// decoration competing with foreground text. Was a hand-painted
/// approximation before the real asset file was available; see
/// DECISIONS.md.
class HexPatternBackground extends StatelessWidget {
  final Widget? child;
  final double opacity;

  const HexPatternBackground({super.key, this.child, this.opacity = 0.06});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              // The source asset is a full-contrast image, not a
              // pre-faded overlay — scale opacity up from the caller's
              // (small, calibrated-for-a-plain-stroke-painter) value so
              // the texture still reads once alpha-blended.
              opacity: (opacity * 3).clamp(0.0, 1.0),
              child: Image.asset('assets/images/bg_hex_pattern.png', fit: BoxFit.cover),
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}
