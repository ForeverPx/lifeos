import 'package:flutter/foundation.dart';

@immutable
class DiaryEntry {
  const DiaryEntry({
    required this.headerLine,
    required this.title,
    required this.source,
    required this.tags,
    this.timeLabel,
  });

  /// Full first line after `##`, e.g. `2026-03-04 17:18:00 | 标题`
  final String headerLine;
  final String title;
  final String source;
  final List<String> tags;

  /// Optional short time from header (e.g. `17:18`)
  final String? timeLabel;
}
