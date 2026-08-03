import 'package:flutter/material.dart';

/// Small circular percentage gauge — used for SLA Compliance wherever it
/// shows up (Admin Dashboard, Analytics). `percent` is 0-100; null renders
/// an empty ring with a "—" (no resolved-ticket data to judge yet), rather
/// than a misleading 0%.
class PercentRing extends StatelessWidget {
  final double? percent;
  final Color color;
  final double size;
  final double strokeWidth;

  const PercentRing({
    super.key,
    required this.percent,
    required this.color,
    this.size = 64,
    this.strokeWidth = 7,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        // Stack clips to its bounds by default (Clip.hardEdge). A 3-digit
        // value ("100%") at this font size is wide enough to overflow a
        // small ring, and — found live — the default clip silently cut off
        // the leading digit, turning a real 100% into a displayed "00%".
        // Clip.none guarantees the label is always fully visible even if it
        // spills a couple of pixels past the ring itself.
        clipBehavior: Clip.none,
        children: [
          CircularProgressIndicator(
            value: 1,
            strokeWidth: strokeWidth,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          CircularProgressIndicator(
            value: (percent ?? 0) / 100,
            strokeWidth: strokeWidth,
            color: color,
            strokeCap: StrokeCap.round,
          ),
          Text(
            percent == null ? '—' : '${percent!.round()}%',
            style: TextStyle(
              fontSize: size * 0.2,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
