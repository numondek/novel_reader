import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chapter_image_loader.dart';

/// One picture of an image chapter: the local copy when the chapter
/// was saved for offline reading, otherwise the network picture
/// fetched with the browser-like headers chapter sites require.
class ChapterImage extends ConsumerStatefulWidget {
  const ChapterImage({
    super.key,
    required this.url,
    this.localPath,
    this.referer,
  });

  final String url;
  final String? localPath;
  final String? referer;

  @override
  ConsumerState<ChapterImage> createState() => _ChapterImageState();
}

class _ChapterImageState extends ConsumerState<ChapterImage> {
  late Future<Uint8List> _pending;

  @override
  void initState() {
    super.initState();
    _pending = _load();
  }

  @override
  void didUpdateWidget(covariant ChapterImage old) {
    super.didUpdateWidget(old);

    if (old.url != widget.url || old.referer != widget.referer) {
      _pending = _load();
    }
  }

  Future<Uint8List> _load() {
    return ref
        .read(chapterImageLoaderProvider)
        .load(widget.url, referer: widget.referer);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.localPath;

    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.contain,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) => const _ImageUnavailable(),
      );
    }

    return FutureBuilder<Uint8List>(
      future: _pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return const _ImageUnavailable();
        }

        return Image.memory(
          snapshot.data!,
          fit: BoxFit.contain,
          width: double.infinity,
          errorBuilder:
              (context, error, stackTrace) => const _ImageUnavailable(),
        );
      },
    );
  }
}

class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 220,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text('Image unavailable', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
