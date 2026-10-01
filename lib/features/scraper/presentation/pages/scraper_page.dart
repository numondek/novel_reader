import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/empty_state.dart';

@RoutePage()
class ScraperPage extends StatelessWidget {
  const ScraperPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scraper')),
      body: const EmptyState(
        icon: Icons.travel_explore_outlined,
        title: 'Scraper',
        subtitle: 'Coming soon',
      ),
    );
  }
}
