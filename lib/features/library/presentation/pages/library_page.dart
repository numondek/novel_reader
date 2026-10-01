import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/empty_state.dart';

@RoutePage()
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: const EmptyState(
        icon: Icons.library_books_outlined,
        title: 'Library',
        subtitle: 'Coming soon',
      ),
    );
  }
}
