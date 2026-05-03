import 'package:intl/intl.dart';

import 'checkin_models.dart';

/// ISO week folder id, e.g. `2026-W18` (matches `checkins/2026-W18/` in repo).
class CheckinWeekBounds {
  CheckinWeekBounds({
    required this.weekId,
    required this.monday,
    required this.days,
  }) : assert(days.length == 7);

  final String weekId;
  final DateTime monday;
  final List<DateTime> days;

  static CheckinWeekBounds forLocalDate(DateTime any) {
    final d = DateTime(any.year, any.month, any.day);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final thursday = monday.add(const Duration(days: 3));
    final isoYear = thursday.year;
    final w = isoWeekNumber(d);
    final weekId =
        '$isoYear-W${w.toString().padLeft(2, '0')}';
    final days = List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
    return CheckinWeekBounds(weekId: weekId, monday: monday, days: days);
  }

  /// ISO 8601 week number for [date] (local calendar day).
  static int isoWeekNumber(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final thursday = monday.add(const Duration(days: 3));
    final isoYear = thursday.year;
    final jan4 = DateTime(isoYear, 1, 4);
    final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return 1 + monday.difference(week1Monday).inDays ~/ 7;
  }

  static String ymd(DateTime day) =>
      DateFormat('yyyy-MM-dd').format(DateTime(day.year, day.month, day.day));

  /// How many of [weekDays] have a check-in for [projectId] in [state].
  static int countChecksInWeekDays(
    WeeklyCheckinState state,
    String projectId,
    List<DateTime> weekDays,
  ) {
    final set = state.byProject[projectId];
    if (set == null || set.isEmpty) return 0;
    var n = 0;
    for (final d in weekDays) {
      if (set.contains(ymd(d))) n++;
    }
    return n;
  }
}
