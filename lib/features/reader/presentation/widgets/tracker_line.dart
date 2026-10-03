import 'package:flutter/material.dart';

/// Thin line under the app bar that separates what has been read
/// (filled) from what remains (track).
///
/// Outside narration it follows the scroll position; while narration
/// is active [progress] pins it to the paragraph being read so it
/// moves even when auto-scroll is off.
class TrackerLine extends StatelessWidget {
  const TrackerLine({super.key, required this.scrollController, this.progress});

  final ScrollController scrollController;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 4,
      child: AnimatedBuilder(
        animation: scrollController,
        builder: (context, _) {
          final fraction = progress ?? _scrollFraction();

          return Semantics(
            label: 'Reading progress',
            value: '${(fraction * 100).round()}%',
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  key: const ValueKey('tracker-track'),
                  color: scheme.surfaceContainerHighest,
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: ColoredBox(
                    key: const ValueKey('tracker-fill'),
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Share of the chapter above the current viewport position.
  double _scrollFraction() {
    if (!scrollController.hasClients) return 0;

    final position = scrollController.position;
    if (!position.hasContentDimensions) return 0;

    // Everything fits on screen: nothing remains below.
    if (position.maxScrollExtent <= 0) return 1;

    return (position.pixels / position.maxScrollExtent)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}
