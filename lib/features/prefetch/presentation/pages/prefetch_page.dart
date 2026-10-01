import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/empty_state.dart';

@RoutePage()
class PrefetchPage extends StatelessWidget {
  const PrefetchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prefetch')),
      body: const EmptyState(
        icon: Icons.download_for_offline_outlined,
        title: 'Prefetch',
        subtitle: 'Coming soon',
      ),
    );
  }
}
