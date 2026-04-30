import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CollectCache {
  static const _prefix = 'collect_cache_file:'; // collect_cache_file:<path>

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static String _key(String path) => '$_prefix$path';

  /// Stores content + sha so we can reuse cached values for historical items.
  static Future<void> setFile({
    required String path,
    required String sha,
    required String content,
  }) async {
    final prefs = await _prefs;
    final map = <String, dynamic>{'sha': sha, 'content': content};
    await prefs.setString(_key(path), jsonEncode(map));
  }

  static Future<({String sha, String content})?> getFile(String path) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(path));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final sha = decoded['sha'] as String?;
        final content = decoded['content'] as String?;
        if (sha != null && content != null) return (sha: sha, content: content);
      }
    } catch (_) {
      // ignore corrupt cache entry
    }
    return null;
  }

  static Future<int> clearAll() async {
    final prefs = await _prefs;
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    var removed = 0;
    for (final k in keys) {
      final ok = await prefs.remove(k);
      if (ok) removed++;
    }
    return removed;
  }
}

