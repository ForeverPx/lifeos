import 'package:intl/intl.dart';

import 'llm_diary_tagger.dart';

/// Builds one diary block matching [parseDiaryMarkdown] (multiline `- source:` … `- tags:`).
String buildDiaryMarkdownBlock({
  required DateTime timestamp,
  required DiaryTaggingResult tagging,
  required String body,
}) {
  final headerTs = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
  final title = tagging.title.replaceAll('\n', ' ').trim();
  final tagsLine = tagging.tags.join(' ');
  final b = body.replaceAll('\r\n', '\n');
  return '## $headerTs | $title\n- source:\n$b\n- tags: $tagsLine';
}
