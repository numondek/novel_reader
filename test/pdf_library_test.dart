import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/library/domain/models/pdf_library_item.dart';
import 'package:novel_reader/features/library/domain/services/pdf_file_store.dart';
import 'package:novel_reader/features/library/presentation/providers/pdf_library_provider.dart';

class _FakePdfFileStore implements PdfFileStore {
  final retained = <String, String>{};
  final removed = <String>[];
  var _count = 0;

  @override
  Future<String> retain(String sourcePath, String fileName) async {
    final stored = '/store/${_count++}_$fileName';
    retained[sourcePath] = stored;
    return stored;
  }

  @override
  Future<void> remove(String path) async {
    removed.add(path);
  }
}

void main() {
  late ProviderContainer container;
  late _FakePdfFileStore store;

  setUp(() {
    store = _FakePdfFileStore();
    container = ProviderContainer(
      overrides: [pdfFileStoreProvider.overrideWithValue(store)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  PdfLibraryController controller() =>
      container.read(pdfLibraryProvider.notifier);

  test('add retains the file and records the entry', () async {
    final item = await controller().add(
      sourcePath: '/tmp/source.pdf',
      fileName: 'A Great Tale.pdf',
    );

    final list = await container.read(pdfLibraryProvider.future);

    expect(store.retained['/tmp/source.pdf'], item.path);
    expect(list, hasLength(1));
    expect(list.single.path, item.path);
    expect(list.single.title, 'A Great Tale');
    expect(list.single.lastPage, 1);
    expect(list.single.pageCount, 0);
  });

  test('savePosition remembers the page and the total', () async {
    final item = await controller().add(
      sourcePath: '/a.pdf',
      fileName: 'a.pdf',
    );

    await controller().savePosition(item.path, page: 7, pageCount: 12);
    final entry = (await container.read(pdfLibraryProvider.future)).single;
    expect(entry.lastPage, 7);
    expect(entry.pageCount, 12);

    // An unknown page count keeps the stored total.
    await controller().savePosition(item.path, page: 8);
    final refreshed =
        (await container.read(pdfLibraryProvider.future)).single;
    expect(refreshed.lastPage, 8);
    expect(refreshed.pageCount, 12);
  });

  test('savePosition ignores files that are not in the library',
      () async {
    await controller().savePosition('/missing.pdf', page: 3, pageCount: 9);

    final list = await container.read(pdfLibraryProvider.future);
    expect(list, isEmpty);
  });

  test('remove drops the entry and deletes the stored file', () async {
    final first = await controller().add(
      sourcePath: '/1.pdf',
      fileName: 'one.pdf',
    );
    await controller().add(
      sourcePath: '/2.pdf',
      fileName: 'two.pdf',
    );

    await controller().remove(first.path);

    final list = await container.read(pdfLibraryProvider.future);
    expect(list.map((entry) => entry.title), ['two']);
    expect(store.removed, [first.path]);
    expect(store.retained.containsKey('/2.pdf'), isTrue);
  });

  test('json round trip keeps the entry', () {
    final item = PdfLibraryItem(
      path: '/x/doc.pdf',
      title: 'Doc',
      addedAt: DateTime.fromMillisecondsSinceEpoch(1234),
      lastPage: 4,
      pageCount: 20,
    );

    final restored = PdfLibraryItem.fromJson(item.toJson());

    expect(restored.path, item.path);
    expect(restored.title, item.title);
    expect(restored.addedAt, item.addedAt);
    expect(restored.lastPage, 4);
    expect(restored.pageCount, 20);
  });

  test('titleFromFileName strips the pdf extension', () {
    expect(PdfLibraryItem.titleFromFileName('Story.pdf'), 'Story');
    expect(PdfLibraryItem.titleFromFileName('story.PDF'), 'story');
    expect(PdfLibraryItem.titleFromFileName('  notes.pdf  '), 'notes');
    expect(PdfLibraryItem.titleFromFileName('.pdf'), '.pdf');
    expect(PdfLibraryItem.titleFromFileName('plain.txt'), 'plain.txt');
  });
}
