import 'package:flutter/foundation.dart';

@immutable
class CollectItem {
  const CollectItem({
    required this.day,
    required this.path,
    required this.fileName,
    required this.title,
    required this.body,
    required this.preview,
    required this.tags,
  });

  /// Day folder name, e.g. 2026-04-30
  final DateTime day;

  /// GitHub content path relative to repo root, e.g. collect/2026-04-30/foo.md
  final String path;

  final String fileName;
  final String title;
  final String body;

  /// A short preview generated from [body].
  final String preview;

  /// Parsed from markdown body, like `#flutter #ai`.
  final List<String> tags;
}

