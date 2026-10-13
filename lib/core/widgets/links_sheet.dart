import 'package:flutter/material.dart';

import '../utils/url_utils.dart';

/// Shows the links an entry carries — each one tappable through
/// [onOpen] — and asks for another one, resolving with the added
/// URL or `null` when the sheet is dismissed without one.
///
/// Tapping a listed link closes the sheet and hands the URL to
/// [onOpen], so the caller acts on it once the sheet is gone.
Future<String?> showLinksSheet(
  BuildContext context, {
  required String title,
  required String hint,
  required List<String> links,
  void Function(String url)? onOpen,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder:
        (context) => SafeArea(
          child: LinksSheet(
            title: title,
            hint: hint,
            links: links,
            onOpen: onOpen,
          ),
        ),
  );
}

/// The contents of [showLinksSheet]: the links already kept, and
/// the field that adds one more.
class LinksSheet extends StatefulWidget {
  const LinksSheet({
    super.key,
    required this.title,
    required this.hint,
    this.links = const [],
    this.onOpen,
  });

  final String title;
  final String hint;
  final List<String> links;
  final void Function(String url)? onOpen;

  @override
  State<LinksSheet> createState() => _LinksSheetState();
}

class _LinksSheetState extends State<LinksSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = normalizeUrl(_controller.text);

    if (url == null) {
      setState(() => _error = 'Enter a valid URL');
      return;
    }

    Navigator.of(context).pop(url);
  }

  void _open(String url) {
    final onOpen = widget.onOpen;

    Navigator.of(context).pop();

    onOpen?.call(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onOpen = widget.onOpen;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            widget.hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.links.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final link in widget.links)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.link),
                title: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing:
                    onOpen == null ? null : const Icon(Icons.chevron_right),
                onTap: onOpen == null ? null : () => _open(link),
              ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: widget.links.isEmpty,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'URL',
              hintText: 'https://example.com/…',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error == null) return;
              setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
