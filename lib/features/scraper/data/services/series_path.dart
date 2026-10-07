import 'chapter_link_finder.dart';

/// The path a series' chapters hang from.
///
/// A chapter segment (`chapter-108`, `ep-100`, a bare `45`) is
/// trimmed off the end; anything else is taken as the series page
/// itself.
String seriesPathOf(Uri url) {
  var path = url.path;

  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  // A marker may sit in its own folder (`/chapter/116`), so one
  // slash is allowed to reach the number — but only one, or a
  // series named `chapter-5` would eat the segment after it.
  const chapterTail =
      r'(?:^|[-_/])(?:chapter|episode|ch|ep)(?:[\s._-]*/)?[\s._-]*#?\d+[^/]*$';

  final marker = RegExp(chapterTail, caseSensitive: false).firstMatch(path);
  if (marker != null) {
    return _trim(path.substring(0, marker.start));
  }

  final segments = [
    for (final segment in path.split('/'))
      if (segment.isNotEmpty) segment,
  ];

  if (segments.isNotEmpty && RegExp(r'^\d+$').hasMatch(segments.last)) {
    segments.removeLast();
    return _trim('/${segments.join('/')}');
  }

  // A chapter file may carry its number in the file name
  // (`everlasting-dragon-emperor_2.html`): the series is the same
  // file without the number.
  if (segments.isNotEmpty) {
    final numbered = RegExp(
      r'^(.+)_(\d+)\.html$',
      caseSensitive: false,
    ).firstMatch(segments.last);

    if (numbered != null) {
      segments[segments.length - 1] = '${numbered.group(1)}.html';
      return _trim('/${segments.join('/')}');
    }
  }

  return _trim(path);
}

/// The series a chapter hangs from: its path with the chapter
/// segment trimmed off, and the directory it sits in when the file
/// name carries no marker at all (`special-2`).
///
/// Never the bare directory on a chapter that does carry one —
/// readers such as `/reader/en/pick-me-up-chapter-161-eng-li/` put
/// every series of the site in one shared folder, and only the
/// trimmed slug tells them apart.
String seriesPathFor(String chapterUrl) {
  final uri = Uri.tryParse(chapterUrl);

  if (uri == null) {
    return chapterDirectoryOf(chapterUrl);
  }

  final series = seriesPathOf(uri);

  return series == _trim(uri.path) ? chapterDirectoryOf(chapterUrl) : series;
}

/// The series path the chapters of [links] share: [seriesPathFor]
/// of each, cut down to the part every one of them has in common.
/// Better than guessing from the open page when a contents page
/// lives somewhere else entirely (`/latest`).
String? seriesPathFrom(List<ChapterLink> links) {
  if (links.isEmpty) {
    return null;
  }

  var common = _segmentsOf(seriesPathFor(links.first.url));

  for (final link in links.skip(1)) {
    final segments = _segmentsOf(seriesPathFor(link.url));
    var index = 0;

    while (index < common.length &&
        index < segments.length &&
        common[index] == segments[index]) {
      index++;
    }

    common = common.sublist(0, index);

    if (common.isEmpty) {
      return null;
    }
  }

  if (common.isEmpty) {
    return null;
  }

  return '/${common.join('/')}';
}

/// Groups every chapter of one series under a single key, whether
/// the user opened the series page or a chapter of it.
String manhwaNovelKey(Uri url, {List<ChapterLink> links = const []}) {
  final path = seriesPathFrom(links) ?? seriesPathOf(url);

  return 'manhwa:${url.host}${_trim(path)}';
}

String _trim(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }

  return path;
}

List<String> _segmentsOf(String path) {
  return [
    for (final segment in path.split('/'))
      if (segment.isNotEmpty) segment,
  ];
}
