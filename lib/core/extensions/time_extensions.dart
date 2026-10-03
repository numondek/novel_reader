extension DateTimeX on DateTime {
  /// Short relative label for list subtitles, e.g. `Just now`,
  /// `12 min ago`, `3 d ago`, falling back to a date.
  String get relativeTime {
    final difference = DateTime.now().difference(this);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }

    if (difference.inHours < 1) {
      return '${difference.inMinutes} min ago';
    }

    if (difference.inDays < 1) {
      return '${difference.inHours} h ago';
    }

    if (difference.inDays < 30) {
      return '${difference.inDays} d ago';
    }

    return '$year-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }
}
