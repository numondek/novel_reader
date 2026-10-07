import 'package:flutter/material.dart';

/// Play/pause and navigation bar pinned under the reading area.
class ReaderControls extends StatelessWidget {
  const ReaderControls({
    super.key,
    required this.onFontSize,
    required this.isPlaying,
    required this.isPaused,
    required this.onPlayPause,
    required this.autoScroll,
    required this.onToggleAutoScroll,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    this.showTextControls = true,
    this.autoScrolling = false,
    this.onToggleContinuousAutoScroll,
    this.onScrollSpeed,
  });

  final VoidCallback onFontSize;
  final bool isPlaying;
  final bool isPaused;
  final VoidCallback onPlayPause;
  final bool autoScroll;
  final VoidCallback onToggleAutoScroll;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Hides narration, auto-scroll and font size — controls that
  /// make no sense for picture chapters.
  final bool showTextControls;

  /// Whether a picture chapter is scrolling past on its own right
  /// now — a different auto-scroll from [autoScroll], which follows
  /// the narration of a text chapter.
  final bool autoScrolling;
  final VoidCallback? onToggleContinuousAutoScroll;
  final VoidCallback? onScrollSpeed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: hasPrevious ? onPrevious : null,
              tooltip: 'Previous chapter',
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            if (showTextControls)
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPlayPause,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    isPlaying
                        ? 'Pause'
                        : isPaused
                        ? 'Resume'
                        : 'Play',
                  ),
                ),
              )
            else
              const Spacer(),
            IconButton(
              onPressed: hasNext ? onNext : null,
              tooltip: 'Next chapter',
              icon: const Icon(Icons.skip_next_rounded),
            ),
            if (showTextControls)
              IconButton(
                onPressed: onToggleAutoScroll,
                tooltip: 'Auto-scroll',
                icon: Icon(
                  autoScroll
                      ? Icons.center_focus_strong
                      : Icons.center_focus_weak,
                  color:
                      autoScroll ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
            if (!showTextControls) ...[
              IconButton(
                onPressed: onToggleContinuousAutoScroll,
                tooltip: 'Auto-scroll',
                icon: Icon(
                  autoScrolling
                      ? Icons.center_focus_strong
                      : Icons.center_focus_weak,
                  color:
                      autoScrolling
                          ? Theme.of(context).colorScheme.primary
                          : null,
                ),
              ),
              IconButton(
                onPressed: onScrollSpeed,
                tooltip: 'Scroll speed',
                icon: const Icon(Icons.speed),
              ),
            ],
            if (showTextControls)
              IconButton(
                onPressed: onFontSize,
                tooltip: 'Font size',
                icon: const Icon(Icons.text_fields),
              ),
          ],
        ),
      ),
    );
  }
}
