import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/novels/presentation/pages/novels_page.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';

class _SeededReadNovels extends ReadNovelsController {
  _SeededReadNovels(this.seed);

  final List<ReadNovel> seed;

  @override
  Future<List<ReadNovel>> build() async => seed;
}

List<ReadNovel> seedEntries() {
  return [
    ReadNovel(
      key: 'novel:site.com:Nova',
      url: 'https://site.com/nova/chapter-2',
      novelTitle: 'Nova',
      chapterTitle: 'Chapter 2 - The duel',
      readAt: DateTime.now(),
    ),
    ReadNovel(
      key: 'novel:other.org:Sol',
      url: 'https://other.org/sol/chapter-9',
      novelTitle: 'Sol',
      chapterTitle: 'Chapter 9 - Nightfall',
      readAt: DateTime.now(),
    ),
    ReadNovel(
      key: 'url:site2.com:bare',
      url: 'https://site2.com/bare/chapter-5',
      chapterTitle: 'Chapter 5 - Lost',
      readAt: DateTime.now(),
    ),
    ReadNovel(
      key: 'novel:czbooks.net:開局簽到荒古聖體',
      url: 'https://czbooks.net/n/s6pcm6/ucp0ldl2',
      novelTitle: '開局簽到荒古聖體',
      novelTitleEn: 'Obtaining the Ancient Holy Body',
      chapterTitle: '第4682章 十小聖之首',
      chapterTitleEn: 'Chapter 4682 - Head of the Ten Saints',
      readAt: DateTime.now(),
    ),
  ];
}

Widget buildPage(List<ReadNovel> seed) {
  return ProviderScope(
    overrides: [
      readNovelsProvider.overrideWith(() => _SeededReadNovels(seed)),
    ],
    child: const MaterialApp(home: NovelsPage()),
  );
}

void main() {
  testWidgets('shows novels by name with chapter context',
      (tester) async {
    await tester.pumpWidget(buildPage(seedEntries()));
    await tester.pump();

    expect(find.text('Nova'), findsOneWidget);
    expect(find.text('Sol'), findsOneWidget);
    expect(find.textContaining('Chapter 2 - The duel'), findsOneWidget);
    expect(find.textContaining('site.com'), findsOneWidget);
    expect(find.textContaining('other.org'), findsOneWidget);

    expect(find.text('Chapter 5 - Lost'), findsOneWidget);
    expect(find.textContaining('site2.com'), findsOneWidget);

    expect(
      find.text('Obtaining the Ancient Holy Body'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Chapter 4682 - Head of the Ten Saints'),
      findsOneWidget,
    );
    expect(find.text('開局簽到荒古聖體'), findsNothing);
    expect(find.textContaining('第4682章'), findsNothing);
  });

  testWidgets('delete removes only the tapped entry',
      (tester) async {
    await tester.pumpWidget(buildPage(seedEntries()));
    await tester.pump();

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Nova'), findsNothing);
    expect(find.text('Sol'), findsOneWidget);
    expect(find.text('Chapter 5 - Lost'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelsPage)),
    );
    final remaining = await container.read(readNovelsProvider.future);
    expect(remaining, hasLength(3));
    expect(
      remaining.map((entry) => entry.key),
      containsAll([
        'novel:other.org:Sol',
        'url:site2.com:bare',
        'novel:czbooks.net:開局簽到荒古聖體',
      ]),
    );
  });

  testWidgets('shows an empty state with no entries',
      (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pump();

    expect(find.text('No read novels yet'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
  });
}
