import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../presentation/providers/home_provider.dart';

@RoutePage()
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _urlController =
      TextEditingController();

  static const List<_FeatureTile> _features = [
    _FeatureTile(Icons.menu_book_outlined, 'Novels', 'Browse and search novels'),
    _FeatureTile(Icons.travel_explore_outlined, 'Manhwa', 'Save & read offline'),
    _FeatureTile(Icons.translate_outlined, 'Translation', 'Translate chapters'),
    _FeatureTile(Icons.article_outlined, 'Reader', 'Continue reading'),
    _FeatureTile(Icons.headphones_outlined, 'Audio', 'Listen with TTS'),
    _FeatureTile(Icons.download_for_offline_outlined, 'Prefetch', 'Offline chapters'),
    _FeatureTile(Icons.library_books_outlined, 'Library', 'Your collection'),
    _FeatureTile(Icons.settings_outlined, 'Settings', 'Preferences'),
  ];

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _startReading() {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a novel URL'),
        ),
      );
      return;
    }

    context.router.push(
      NovelImportRoute(
        url: url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final greeting = ref.watch(homeGreetingProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Novel Reader')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(greeting, style: theme.textTheme.displayLarge),
          const SizedBox(height: 4),
          Text(
            'What would you like to do?',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start reading', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    decoration: const InputDecoration(
                      hintText: 'Paste chapter URL',
                      prefixIcon: Icon(Icons.link),
                    ),
                    onSubmitted: (_) => _startReading(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _startReading,
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text('Read'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              for (var i = 0; i < _features.length; i++)
                _FeatureCard(
                  tile: _features[i],
                  onTap: () => _open(context, i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, int index) {
    final route = switch (index) {
      0 => const NovelsRoute(),
      1 => const ScraperRoute(),
      2 => const TranslationRoute(),
      3 => ReaderRoute(),
      4 => const AudioRoute(),
      5 => const PrefetchRoute(),
      6 => const LibraryRoute(),
      _ => const SettingsRoute(),
    };
    context.router.push(route);
  }
}

class _FeatureTile {
  const _FeatureTile(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.tile, required this.onTap});

  final _FeatureTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tile.icon, color: theme.colorScheme.primary),
              const Spacer(),
              Text(tile.title, style: theme.textTheme.titleMedium),
              Text(
                tile.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
