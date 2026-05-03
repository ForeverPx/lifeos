import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'checkin_models.dart';
import 'checkin_week.dart';

class CheckinWeekPanel extends StatelessWidget {
  const CheckinWeekPanel({
    super.key,
    required this.bounds,
    required this.state,
    required this.loading,
    required this.saving,
    required this.onToggle,
    this.showHeading = true,
  });

  final CheckinWeekBounds bounds;
  final WeeklyCheckinState state;
  final bool loading;
  final bool saving;
  final void Function(String projectId, String ymd) onToggle;

  /// When false (e.g. standalone tab with its own AppBar-style title), only week range + rows are shown.
  final bool showHeading;

  static const _shortWeekday = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: FCircularProgress()),
      );
    }

    final rangeLabel =
        '${DateFormat('M月d日', 'zh_CN').format(bounds.days.first)}–'
        '${DateFormat('M月d日', 'zh_CN').format(bounds.days.last)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Row(
            children: [
              Icon(FIcons.listChecks, size: 22, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                '本周打卡',
                style: typography.xl.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                  height: 1.2,
                ),
              ),
              const Spacer(),
              if (saving)
                const FCircularProgress(
                  size: FCircularProgressSizeVariant.sm,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${bounds.weekId} · $rangeLabel',
            style: typography.xs.copyWith(
              color: colors.mutedForeground,
              height: 1.35,
            ),
          ),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${bounds.weekId} · $rangeLabel',
                  style: typography.sm.copyWith(
                    color: colors.mutedForeground,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
              if (saving)
                const Padding(
                  padding: EdgeInsets.only(left: 8, top: 2),
                  child: FCircularProgress(
                    size: FCircularProgressSizeVariant.sm,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        for (var i = 0; i < kCheckinProjects.length; i++) ...[
          _ProjectRow(
            def: kCheckinProjects[i],
            days: bounds.days,
            state: state,
            saving: saving,
            shortWeekday: _shortWeekday,
            onToggle: onToggle,
            weekProgress: CheckinWeekBounds.countChecksInWeekDays(
              state,
              kCheckinProjects[i].id,
              bounds.days,
            ),
          ),
          if (i < kCheckinProjects.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.def,
    required this.days,
    required this.state,
    required this.saving,
    required this.shortWeekday,
    required this.onToggle,
    required this.weekProgress,
  });

  final CheckinProjectDef def;
  final List<DateTime> days;
  final WeeklyCheckinState state;
  final bool saving;
  final List<String> shortWeekday;
  final void Function(String projectId, String ymd) onToggle;
  final int weekProgress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final target = def.weeklyTarget;
    final goalMet = weekProgress >= target;

    return Material(
      color: goalMet
          ? colors.primary.withValues(alpha: 0.12)
          : colors.secondary.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    def.label,
                    style: typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                    ),
                  ),
                ),
                Text(
                  '$weekProgress / $target 次',
                  style: typography.xs.copyWith(
                    color: goalMet ? colors.primary : colors.mutedForeground,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                if (goalMet) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: '本周目标已达成',
                    child: Icon(
                      FIcons.badgeCheck,
                      size: 22,
                      color: colors.primary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _DayChip(
                      weekdayLabel: shortWeekday[i],
                      checked: state.isChecked(
                        def.id,
                        CheckinWeekBounds.ymd(days[i]),
                      ),
                      enabled: !saving,
                      onTap: () => onToggle(
                        def.id,
                        CheckinWeekBounds.ymd(days[i]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.weekdayLabel,
    required this.checked,
    required this.enabled,
    required this.onTap,
  });

  final String weekdayLabel;
  final bool checked;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    return Material(
      color: checked
          ? colors.primary.withValues(alpha: 0.35)
          : colors.muted.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                weekdayLabel,
                style: typography.xs2.copyWith(
                  fontWeight: FontWeight.w600,
                  color: checked ? colors.primaryForeground : colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                checked ? FIcons.circleCheck : FIcons.circle,
                size: 20,
                color: checked ? colors.primary : colors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
