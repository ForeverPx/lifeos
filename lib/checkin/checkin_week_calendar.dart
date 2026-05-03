import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'checkin_global_stats.dart';
import 'checkin_models.dart';
import 'checkin_week.dart';

/// Recent ISO weeks: each row shows the week id + overall status, then each habit's progress.
class CheckinRecentWeeksCalendar extends StatelessWidget {
  const CheckinRecentWeeksCalendar({
    super.key,
    required this.weeks,
    required this.statsByWeekId,
    required this.currentWeekId,
    required this.currentWeekLiveState,
    this.loading = false,
  });

  /// Newest-first week bounds (see [CheckinWeekBounds.lastNWeeksNewestFirst]).
  final List<CheckinWeekBounds> weeks;

  /// Server-side rollups from `_global_checkin_stats.json` (may omit weeks).
  final Map<String, CheckinWeekRollup> statsByWeekId;

  final String currentWeekId;
  final WeeklyCheckinState? currentWeekLiveState;

  final bool loading;

  CheckinWeekRollup? _rollupFor(CheckinWeekBounds b) {
    if (b.weekId == currentWeekId && currentWeekLiveState != null) {
      return CheckinWeekRollup.fromState(currentWeekLiveState!, b);
    }
    return statsByWeekId[b.weekId];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(FIcons.calendarDays, size: 22, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              '周日历',
              style: typography.xl.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.foreground,
                height: 1.2,
              ),
            ),
            if (loading) ...[
              const SizedBox(width: 10),
              const FCircularProgress(
                size: FCircularProgressSizeVariant.sm,
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '每行一周：上方为周标识与总体达标情况，下方列出各打卡项的进度与是否达标。',
          style: typography.xs.copyWith(
            color: colors.mutedForeground,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        for (final b in weeks) _WeekRow(bounds: b, rollup: _rollupFor(b)),
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.bounds,
    required this.rollup,
  });

  final CheckinWeekBounds bounds;
  final CheckinWeekRollup? rollup;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final hasData = rollup != null;
    final allMet = rollup?.allMet ?? false;
    final met = rollup?.habitsMet ?? 0;
    final total = rollup?.habitsTotal ?? kCheckinProjects.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.secondary.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    bounds.weekId,
                    style: typography.sm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.foreground,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (!hasData)
                    Text(
                      '暂无统计',
                      style: typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    )
                  else if (allMet)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FIcons.badgeCheck, size: 20, color: colors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '本周全达成',
                          style: typography.xs.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.muted.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$met / $total 项达标',
                        style: typography.xs.copyWith(
                          color: colors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < kCheckinProjects.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _HabitLine(
                  def: kCheckinProjects[i],
                  rollup: rollup,
                  hasWeekData: hasData,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitLine extends StatelessWidget {
  const _HabitLine({
    required this.def,
    required this.rollup,
    required this.hasWeekData,
  });

  final CheckinProjectDef def;
  final CheckinWeekRollup? rollup;
  final bool hasWeekData;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    final CheckinHabitRollup? r =
        hasWeekData && rollup != null ? rollup!.byHabit[def.id] : null;
    final count = r?.count ?? 0;
    final target = r?.target ?? def.weeklyTarget;
    final met = r?.met ?? false;
    final showPlaceholder = !hasWeekData;

    return Row(
      children: [
        Expanded(
          child: Text(
            def.label,
            style: typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: showPlaceholder ? colors.mutedForeground : colors.foreground,
            ),
          ),
        ),
        Text(
          showPlaceholder ? '—' : '$count / $target 次',
          style: typography.xs.copyWith(
            color: showPlaceholder ? colors.border : colors.mutedForeground,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(width: 8),
        if (showPlaceholder)
          Icon(FIcons.circleMinus, size: 18, color: colors.border)
        else if (met)
          Tooltip(
            message: '该项本周已达标',
            child: Icon(FIcons.circleCheck, size: 20, color: colors.primary),
          )
        else
          Tooltip(
            message: '该项本周未达标',
            child: Icon(FIcons.circle, size: 20, color: colors.border),
          ),
      ],
    );
  }
}
