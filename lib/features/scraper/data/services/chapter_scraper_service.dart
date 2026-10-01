import '../../../novels/domain/models/chapter.dart';
import '../repositories/scraper_repository.dart';

class ChapterScraperService {
  ChapterScraperService({
    required ScraperRepository repository,
  }) : _repository = repository;

  final ScraperRepository _repository;

  Future<Chapter> fetchAndParse(String url) async {
    final extracted = await _repository.extractChapter(url);

    return Chapter(
      id: extracted.url,
      url: extracted.url,
      title: extracted.title,
      paragraphs: extracted.paragraphs,
      previousChapterUrl: extracted.previousChapterUrl,
      nextChapterUrl: extracted.nextChapterUrl,
      status: ChapterStatus.extracted,
    );
  }
}
