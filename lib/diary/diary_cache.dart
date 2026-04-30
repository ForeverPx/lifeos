import 'package:shared_preferences/shared_preferences.dart';

class DiaryCache {
  static const _dayPrefix = 'diary_cache_day:'; // diary_cache_day:YYYY-MM-DD

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static String dayKey(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$_dayPrefix$y-$m-$d';
  }

  static Future<String?> getDayMarkdown({
    required int year,
    required int month,
    required int day,
  }) async {
    final prefs = await _prefs;
    final key = dayKey(DateTime(year, month, day));
    return prefs.getString(key);
  }

  static Future<void> setDayMarkdown({
    required int year,
    required int month,
    required int day,
    required String markdown,
  }) async {
    final prefs = await _prefs;
    final key = dayKey(DateTime(year, month, day));
    await prefs.setString(key, markdown);
  }

  static Future<int> clearAll() async {
    final prefs = await _prefs;
    final keys = prefs.getKeys().where((k) => k.startsWith(_dayPrefix)).toList();
    var removed = 0;
    for (final k in keys) {
      final ok = await prefs.remove(k);
      if (ok) removed++;
    }
    return removed;
  }
}

