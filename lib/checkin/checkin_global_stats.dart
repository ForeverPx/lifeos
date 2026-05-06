import 'checkin_models.dart';
import 'checkin_week.dart';

/// One habit's numbers for a single ISO week (stored in global stats JSON).
class CheckinHabitRollup {
  const CheckinHabitRollup({
    required this.count,
    required this.target,
    required this.met,
  });

  final int count;
  final int target;
  final bool met;

  Map<String, dynamic> toJson() => {
        'count': count,
        'target': target,
        'met': met,
      };

  static CheckinHabitRollup? fromJson(Map<String, dynamic>? map) {
    if (map == null) return null;
    final c = map['count'];
    final t = map['target'];
    final m = map['met'];
    if (c is! int || t is! int || m is! bool) return null;
    return CheckinHabitRollup(count: c, target: t, met: m);
  }
}

/// Aggregated snapshot for one week (for calendar + `_global_checkin_stats.json`).
class CheckinWeekRollup {
  CheckinWeekRollup({
    required this.weekId,
    required this.byHabit,
    required this.habitsMet,
    required this.habitsTotal,
    required this.allMet,
  });

  final String weekId;
  final Map<String, CheckinHabitRollup> byHabit;
  final int habitsMet;
  final int habitsTotal;
  final bool allMet;

  factory CheckinWeekRollup.fromState(
    WeeklyCheckinState state,
    CheckinWeekBounds bounds,
  ) {
    final byHabit = <String, CheckinHabitRollup>{};
    var metCount = 0;
    for (final def in kCheckinProjects) {
      final c = CheckinWeekBounds.countChecksInWeekDays(
        state,
        def.id,
        bounds.days,
      );
      final met = c >= def.weeklyTarget;
      if (met) metCount++;
      byHabit[def.id] = CheckinHabitRollup(
        count: c,
        target: def.weeklyTarget,
        met: met,
      );
    }
    return CheckinWeekRollup(
      weekId: bounds.weekId,
      byHabit: byHabit,
      habitsMet: metCount,
      habitsTotal: kCheckinProjects.length,
      allMet: metCount == kCheckinProjects.length,
    );
  }

  Map<String, dynamic> toJson() {
    final habits = <String, dynamic>{};
    for (final def in kCheckinProjects) {
      final r = byHabit[def.id];
      if (r != null) habits[def.id] = r.toJson();
    }
    return {
      'weekId': weekId,
      'habits': habits,
      'habitsMet': habitsMet,
      'habitsTotal': habitsTotal,
      'allMet': allMet,
    };
  }

  static CheckinWeekRollup? fromJson(String weekId, Map<String, dynamic> map) {
    final habitsRaw = map['habits'];
    final byHabit = <String, CheckinHabitRollup>{};
    if (habitsRaw is Map<String, dynamic>) {
      for (final def in kCheckinProjects) {
        final h = habitsRaw[def.id];
        if (h is Map<String, dynamic>) {
          final r = CheckinHabitRollup.fromJson(h);
          if (r != null) byHabit[def.id] = r;
        }
      }
    }
    final hm = map['habitsMet'];
    final ht = map['habitsTotal'];
    final am = map['allMet'];
    final derivedMet = byHabit.values.where((r) => r.met).length;
    return CheckinWeekRollup(
      weekId: map['weekId'] as String? ?? weekId,
      byHabit: byHabit,
      habitsMet: hm is int ? hm : derivedMet,
      habitsTotal: ht is int ? ht : kCheckinProjects.length,
      allMet: am is bool ? am : (byHabit.length == kCheckinProjects.length &&
          byHabit.values.every((r) => r.met)),
    );
  }
}

/// Root document at `checkins/_global_checkin_stats.json`.
class CheckinGlobalStatsDocument {
  CheckinGlobalStatsDocument({
    required this.weeks,
  });

  final Map<String, CheckinWeekRollup> weeks;

  Map<String, dynamic> toJson() {
    final w = <String, dynamic>{};
    for (final e in weeks.entries) {
      w[e.key] = e.value.toJson();
    }
    return {
      'version': 2,
      'weeks': w,
    };
  }

  static CheckinGlobalStatsDocument empty() =>
      CheckinGlobalStatsDocument(weeks: {});

  static CheckinGlobalStatsDocument fromJson(Map<String, dynamic> map) {
    final raw = map['weeks'];
    final weeks = <String, CheckinWeekRollup>{};
    if (raw is Map<String, dynamic>) {
      // v2 format: { "weeks": { "2026-W18": { ... }, ... } }
      for (final e in raw.entries) {
        final v = e.value;
        if (v is Map<String, dynamic>) {
          final r = CheckinWeekRollup.fromJson(e.key, v);
          if (r != null) weeks[e.key] = r;
        }
      }
    } else if (raw is List) {
      // Legacy format tolerance: { "weeks": [ { "weekId": "2026-W18", ... }, ... ] }
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['weekId'];
        if (id is! String || id.trim().isEmpty) continue;
        final r = CheckinWeekRollup.fromJson(id.trim(), item);
        if (r != null) weeks[id.trim()] = r;
      }
    }
    return CheckinGlobalStatsDocument(weeks: weeks);
  }

  CheckinGlobalStatsDocument upsertWeek(CheckinWeekRollup rollup) {
    final next = Map<String, CheckinWeekRollup>.from(weeks);
    next[rollup.weekId] = rollup;
    return CheckinGlobalStatsDocument(weeks: next);
  }
}

class SaveWeekOutcome {
  const SaveWeekOutcome({
    required this.weekFileSha,
    required this.globalStatsUpdated,
    this.globalStatsError,
    this.globalStatsDocument,
    this.globalStatsSha,
  });

  final String weekFileSha;
  final bool globalStatsUpdated;
  final String? globalStatsError;
  final CheckinGlobalStatsDocument? globalStatsDocument;
  final String? globalStatsSha;
}

/// Result of reading `checkins/_global_checkin_stats.json`.
class CheckinGlobalStatsSnapshot {
  const CheckinGlobalStatsSnapshot({
    required this.document,
    required this.fileSha,
  });

  final CheckinGlobalStatsDocument document;
  final String? fileSha;
}
