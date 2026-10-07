/// Reading-order helpers shared by the scraper UI and the batch
/// saver.
///
/// Chapter names come in many shapes — "Chapter 12", "12. The duel",
/// "ep-100" — so the number is read from the title when it carries
/// one and from the URL otherwise.
int? chapterNumberOf(String title, String url) {
  return _fromTitle(title) ?? _fromUrl(url);
}

final RegExp _markerPattern = RegExp(
  r'(?:chapter|episode|ch|ep)[\s._/-]*#?(\d+)',
  caseSensitive: false,
);

final RegExp _leadingNumber = RegExp(r'^\s*#?(\d+)');

final RegExp _pathNumber = RegExp(r'(?:^|[-_/])(\d+)(?:/|$)');

final RegExp _digit = RegExp(r'\d');

/// The line a chapter list shows: [title] as it is when it already
/// carries a number, and the number found in [url] in front of it
/// otherwise — so a row never hides which chapter it is.
String chapterLabelOf(String title, String url) {
  final text = title.trim();

  if (text.isEmpty) {
    final number = _fromUrl(url);
    return number == null ? text : '#$number';
  }

  if (text.contains(_digit)) {
    return text;
  }

  final number = _fromUrl(url);

  return number == null ? text : '#$number · $text';
}

int? _fromTitle(String title) {
  final marker = _markerPattern.firstMatch(title);

  if (marker != null) {
    final number = int.tryParse(marker.group(1) ?? '');
    if (number != null) {
      return number;
    }
  }

  final leading = _leadingNumber.firstMatch(title);

  return leading == null ? null : int.tryParse(leading.group(1)!);
}

int? _fromUrl(String url) {
  final marker = _markerPattern.firstMatch(url);

  if (marker != null) {
    final number = int.tryParse(marker.group(1) ?? '');
    if (number != null) {
      return number;
    }
  }

  final path = _pathNumber.firstMatch(url);

  return path == null ? null : int.tryParse(path.group(1)!);
}

/// Sorts [chapters] oldest-first when every entry carries a chapter
/// number, and hands back the order it came in otherwise — a list
/// that cannot be ordered is left alone rather than shuffled.
List<T> chaptersInReadingOrder<T>(
  List<T> chapters, {
  required String Function(T) title,
  required String Function(T) url,
}) {
  if (chapters.length < 2) {
    return chapters;
  }

  final numbers = <int>[];

  for (final chapter in chapters) {
    final number = chapterNumberOf(title(chapter), url(chapter));

    if (number == null) {
      return List<T>.of(chapters);
    }

    numbers.add(number);
  }

  final order = List<int>.generate(chapters.length, (index) => index)
    ..sort((a, b) {
      final byNumber = numbers[a].compareTo(numbers[b]);

      return byNumber != 0 ? byNumber : a.compareTo(b);
    });

  return [for (final index in order) chapters[index]];
}
