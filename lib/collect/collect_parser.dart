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

String normalizeBody(String content) {
  final t = content.replaceAll('\r\n', '\n').trim();
  return t;
}

String _fallbackTitle(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot > 0) return fileName.substring(0, dot);
  return fileName;
}

