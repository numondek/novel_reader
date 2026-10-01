extension StringX on String {
  String get capitalize =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  String truncate(int maxLength) =>
      length <= maxLength ? this : '${substring(0, maxLength).trimRight()}…';

  String get stripHtml => replaceAll(RegExp(r'<[^>]*>'), '').trim();

  bool get isBlank => trim().isEmpty;

  String collapseWhitespace() => replaceAll(RegExp(r'\s+'), ' ').trim();
}
