import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/manhwa_series.dart';

/// The cover that goes on the front of a shelf card, falling back
/// to a download while it arrives and to a plain icon when the
/// site never offered one.
class ManhwaCover extends StatelessWidget {
  const ManhwaCover({super.key, required this.series, this.fit = BoxFit.cover});

  final ManhwaSeries series;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final path = series.coverPath;

    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        fit: fit,
        errorBuilder:
            (context, error, stackTrace) => const ManhwaCoverPlaceholder(),
      );
    }

    final url = series.coverUrl;

    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: fit,
        errorBuilder:
            (context, error, stackTrace) => const ManhwaCoverPlaceholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }

          return const ManhwaCoverPlaceholder(icon: Icons.image_outlined);
        },
      );
    }

    return const ManhwaCoverPlaceholder();
  }
}

class ManhwaCoverPlaceholder extends StatelessWidget {
  const ManhwaCoverPlaceholder({
    super.key,
    this.icon = Icons.menu_book_outlined,
  });

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          size: 32,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
