import 'diary_models.dart';

/// Removes the `## …` block whose first line (after `## `) equals [headerLine] trim-for-trim.
///
/// Returns `null` if no matching block. Returns `''` when the file should be deleted (no content left).
String? removeDiaryBlockByHeaderLine(String raw, String headerLine) {
  final normalized = raw.replaceAll('\r\n', '\n');
  final target = headerLine.trim();
  if (target.isEmpty) return null;

  final parts = normalized.split(RegExp(r'^## ', multiLine: true));

  if (parts.length == 1) {
    final entries = parseDiaryMarkdown(normalized);
    final match = entries.where((e) => e.headerLine.trim() == target).length;
    if (match == 0) return null;
    if (entries.length == 1) {
      return '';
    }
    return null;
  }

  final kept = <String>[parts[0]];
  var removed = false;
  for (var i = 1; i < parts.length; i++) {
    final chunk = parts[i];
    final nl = chunk.indexOf('\n');
    final firstLine = (nl == -1 ? chunk : chunk.substring(0, nl)).trim();
    if (firstLine == target) {
      removed = true;
      continue;
    }
    kept.add(chunk);
  }
  if (!removed) return null;
  return _joinDiarySplitParts(kept).trimRight();
}

String _joinDiarySplitParts(List<String> kept) {
  if (kept.length == 1) {
    return kept[0];
  }
  final b = StringBuffer(kept[0]);
  for (var i = 1; i < kept.length; i++) {
    final seg = kept[i];
    if (seg.trim().isEmpty) continue;
    b.write('## ');
    b.write(seg);
  }
  return b.toString();
}

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
    final lines = rest.split('\n');
    var i = 0;
    while (i < lines.length) {
      final t = lines[i].trim();
      if (t.startsWith('- source:')) {
        final after = t.substring('- source:'.length);
        final inline = after.trimLeft();
        final buf = StringBuffer(inline.trimRight());
        i++;
        while (i < lines.length) {
          final u = lines[i].trim();
          if (u.startsWith('- tags:')) {
            final rawTags = u.substring('- tags:'.length).trim();
            tags.addAll(_parseTagTokens(rawTags));
            i++;
            break;
          }
          if (buf.isNotEmpty) {
            buf.writeln();
          }
          buf.write(lines[i]);
          i++;
        }
        source = buf.toString();
        continue;
      }
      if (t.startsWith('- tags:')) {
        final rawTags = t.substring('- tags:'.length).trim();
        tags.addAll(_parseTagTokens(rawTags));
      }
      i++;
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
