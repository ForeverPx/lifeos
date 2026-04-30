import 'diary_models.dart';

/// Parses markdown files where each block starts with `## date | title`
/// followed by `- source:` and `- tags:` lines.
List<DiaryEntry> parseDiaryMarkdown(String raw) {
  final text = raw.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return [];

  final parts = text.split(RegExp(r'^## ', multiLine: true));
  final out = <DiaryEntry>[];

  for (final part in parts) {
    final block = part.trim();
    if (block.isEmpty) continue;

    final nl = block.indexOf('\n');
    final firstLine = nl == -1 ? block : block.substring(0, nl);
    final rest = nl == -1 ? '' : block.substring(nl + 1);

    String source = '';
    final tags = <String>[];
    for (final line in rest.split('\n')) {
      final t = line.trim();
      if (t.startsWith('- source:')) {
        source = t.substring('- source:'.length).trim();
      } else if (t.startsWith('- tags:')) {
        final rawTags = t.substring('- tags:'.length).trim();
        tags.addAll(_parseTagTokens(rawTags));
      }
    }

    final pipe = firstLine.lastIndexOf(' | ');
    final title = pipe == -1
        ? firstLine.trim()
        : firstLine.substring(pipe + 3).trim();
    final timeLabel = _extractTimeLabel(firstLine);

    out.add(
      DiaryEntry(
        headerLine: firstLine,
        title: title,
        source: source,
        tags: tags,
        timeLabel: timeLabel,
      ),
    );
  }

  if (out.isEmpty) {
    final first = text.split('\n').first.trim();
    final title = first
        .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '')
        .trim();
    out.add(
      DiaryEntry(
        headerLine: first,
        title: title.isEmpty ? '未命名记录' : title,
        source: text,
        tags: const [],
      ),
    );
  }

  return out;
}

List<String> _parseTagTokens(String rawTags) {
  final re = RegExp(r'#[^\s#]+');
  return re.allMatches(rawTags).map((m) => m.group(0)!).toList();
}

String? _extractTimeLabel(String firstLine) {
  final re = RegExp(r'\b(\d{1,2}:\d{2})\b');
  final m = re.firstMatch(firstLine);
  return m?.group(1);
}
