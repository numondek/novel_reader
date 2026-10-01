final RegExp _cjkPattern = RegExp(
  r'[一-鿿鿿㐀-䶿぀-ヿ가-힯]',
);

/// True when [text] contains Chinese, Japanese or Korean characters.
bool containsCjk(String text) {
  return _cjkPattern.hasMatch(text);
}
