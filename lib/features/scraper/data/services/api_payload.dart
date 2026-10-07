import 'dart:convert';

/// The JSON object [body] carries, wherever it comes from.
///
/// A direct HTTP call returns bare JSON; the browser-session
/// fallback returns the same payload as a rendered document, so
/// whatever wraps the braces comes off first.
Map<String, dynamic> decodeJsonPayload(String body) {
  var text = body.trim();

  if (text.startsWith('<')) {
    final pre = RegExp(
      r'<pre[^>]*>([\s\S]*?)</pre>',
      caseSensitive: false,
    ).firstMatch(text);

    final wrapped = RegExp(
      r'<body[^>]*>([\s\S]*?)</body>',
      caseSensitive: false,
    ).firstMatch(text);

    text = _unescapeHtml(pre?.group(1) ?? wrapped?.group(1) ?? text);
  }

  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');

  if (start >= 0 && end > start) {
    text = text.substring(start, end + 1);
  }

  try {
    final decoded = jsonDecode(text);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    // Fall through: callers treat an empty map as "no payload".
  }

  return const {};
}

String _unescapeHtml(String text) {
  return text
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
