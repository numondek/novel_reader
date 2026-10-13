import 'package:flutter/material.dart';

import '../utils/url_utils.dart';

/// Asks for a novel or manhwa link and resolves with the URL to open,
/// or `null` when the sheet is dismissed without one.
Future<String?> showAddLinkSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const SafeArea(child: AddLinkSheet()),
  );
}

/// The contents of [showAddLinkSheet]: one URL field and the button
/// that hands the link back to whatever asked for it.
class AddLinkSheet extends StatefulWidget {
  const AddLinkSheet({super.key});

  @override
  State<AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends State<AddLinkSheet> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          Text('Add a link', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Paste the URL of a novel or manhwa.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
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
