import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/empty_state.dart';

@RoutePage()
class TranslationPage extends StatelessWidget {
  const TranslationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Translation')),
      body: const EmptyState(
        icon: Icons.translate_outlined,
        title: 'Translation',
        subtitle: 'Coming soon',
      ),
    );
  }
}
