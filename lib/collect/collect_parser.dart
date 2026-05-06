String titleFromContent({
  required String fileName,
  required String content,
}) {
  final text = content.replaceAll('\r\n', '\n').trimLeft();
  if (text.isEmpty) return _fallbackTitle(fileName);

  final firstLine = text.split('\n').first.trim();
  if (firstLine.startsWith('#')) {
    final t = firstLine.replaceFirst(RegExp(r'^#{1,6}\s*'), '').trim();
    if (t.isNotEmpty) return t;
  }
  if (firstLine.length >= 6 && firstLine.length <= 80) return firstLine;
  return _fallbackTitle(fileName);
}

String previewFromBody(String body, {int maxLen = 160}) {
  var t = body.replaceAll('\r\n', '\n').trim();
  if (t.isEmpty) return '';
  // Collapse whitespace to keep cards compact.
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  if (t.length <= maxLen) return t;
  return '${t.substring(0, maxLen)}…';
}

final _collectTagToken = RegExp(r'#[^\s#]+');

/// Extracts `#tag` tokens from [body], de-duplicated and in order.
List<String> tagsFromCollectBody(String body, {int maxTags = 12}) {
  final text = body.replaceAll('\r\n', '\n');
  final seen = <String>{};
  final out = <String>[];
  for (final m in _collectTagToken.allMatches(text)) {
    final t = (m.group(0) ?? '').trim();
    if (t.isEmpty) continue;
    if (seen.add(t)) {
      out.add(t);
      if (out.length >= maxTags) break;
    }
  }
  return out;
}

final _markdownImageToken = RegExp(r'!\[[^\]]*\]\(([^)\s]+)');

/// Returns the first inline markdown image url in [body], like:
/// `![](https://example.com/a.png)`.
///
/// If none exists, returns null.
String? firstMarkdownImageUrl(String body) {
  final m = _markdownImageToken.firstMatch(body);
  if (m == null) return null;
  final raw = (m.group(1) ?? '').trim();
  if (raw.isEmpty) return null;
  // Markdown allows wrapping url with <...>.
  final v = raw.startsWith('<') && raw.endsWith('>')
      ? raw.substring(1, raw.length - 1).trim()
      : raw;
  return v.isEmpty ? null : v;
}

String normalizeBody(String content) {
  final t = content.replaceAll('\r\n', '\n').trim();
  return t;
}

String _fallbackTitle(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot > 0) return fileName.substring(0, dot);
  return fileName;
}

