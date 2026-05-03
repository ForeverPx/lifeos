/// Fixed habit list stored under `checkins/<weekId>/checkin.json` in my-ai-memory.
class CheckinProjectDef {
  const CheckinProjectDef({
    required this.id,
    required this.label,
    required this.weeklyTarget,
  });

  final String id;
  final String label;

  /// Number of distinct days in the ISO week that count toward the goal.
  final int weeklyTarget;
}

const List<CheckinProjectDef> kCheckinProjects = [
  CheckinProjectDef(id: 'guitar', label: '吉他', weeklyTarget: 4),
  CheckinProjectDef(id: 'vitamins', label: '维生素', weeklyTarget: 4),
  CheckinProjectDef(id: 'blog', label: '博客', weeklyTarget: 3),
  CheckinProjectDef(id: 'fitness', label: '健身', weeklyTarget: 2),
];

/// In-memory state for one ISO week: project id → calendar dates (yyyy-MM-dd) checked.
class WeeklyCheckinState {
  WeeklyCheckinState({
    required this.weekId,
    Map<String, Set<String>>? byProject,
  }) : byProject = byProject ?? {};

  final String weekId;
  final Map<String, Set<String>> byProject;

  bool isChecked(String projectId, String ymd) =>
      byProject[projectId]?.contains(ymd) ?? false;

  WeeklyCheckinState copy() {
    final m = <String, Set<String>>{};
    for (final e in byProject.entries) {
      m[e.key] = Set<String>.from(e.value);
    }
    return WeeklyCheckinState(weekId: weekId, byProject: m);
  }

  WeeklyCheckinState toggle(String projectId, String ymd) {
    final next = copy();
    final set = next.byProject.putIfAbsent(projectId, () => <String>{});
    if (set.contains(ymd)) {
      set.remove(ymd);
    } else {
      set.add(ymd);
    }
    return next;
  }

  Map<String, dynamic> toJson() {
    final projects = <String, dynamic>{};
    for (final def in kCheckinProjects) {
      final dates = (byProject[def.id] ?? const <String>{}).toList()..sort();
      projects[def.id] = dates;
    }
    return {
      'version': 1,
      'weekId': weekId,
      'projects': projects,
    };
  }

  static WeeklyCheckinState fromJson(
    String expectedWeekId,
    Map<String, dynamic> map,
  ) {
    final raw = map['projects'];
    final byProject = <String, Set<String>>{};
    if (raw is Map<String, dynamic>) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is List) {
          byProject[e.key] = v.whereType<String>().toSet();
        }
      }
    }
    final id = map['weekId'] as String? ?? expectedWeekId;
    return WeeklyCheckinState(weekId: id, byProject: byProject);
  }

  static WeeklyCheckinState empty(String weekId) =>
      WeeklyCheckinState(weekId: weekId);
}
