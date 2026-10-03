import 'package:flutter/material.dart';

/// One paragraph of the reading surface; the active one is tinted so
/// the reader can follow narration.
class ReadingParagraph extends StatelessWidget {
  const ReadingParagraph({
    super.key,
    required this.text,
    required this.fontSize,
    required this.isActive,
    required this.onTap,
  });

  final String text;
  final double fontSize;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:
              isActive
                  ? Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(fontSize: fontSize, height: 1.7)),
      ),
    );
  }
}
