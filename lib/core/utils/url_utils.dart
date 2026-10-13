/// Gives a pasted link a scheme when it has none and rejects what is
/// not a usable URL, so every "add a link" entry point can hand the
/// same well-formed address to the flows that open it.
///
/// Returns the trimmed, scheme-complete URL, or `null` when nothing
/// openable is left after trimming.
String? normalizeUrl(String raw) {
  var url = raw.trim();

  if (url.isEmpty) {
    return null;
  }

  var uri = Uri.tryParse(url);

  if (uri == null || !uri.hasScheme) {
    uri = Uri.tryParse('https://$url');
    url = uri?.toString() ?? url;
  }

  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }

  return url;
}
