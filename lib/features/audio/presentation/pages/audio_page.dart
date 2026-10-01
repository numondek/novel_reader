import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/empty_state.dart';

@RoutePage()
class AudioPage extends StatelessWidget {
  const AudioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio')),
      body: const EmptyState(
        icon: Icons.headphones_outlined,
        title: 'Audio',
        subtitle: 'Coming soon',
      ),
    );
  }
}
