import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: cs.primary,
            ),
          ),
        ),
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
              Icon(Icons.task_alt_outlined, size: 22, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                '本周打卡',
                style: GoogleFonts.newsreader(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (saving)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${bounds.weekId} · $rangeLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
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
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
              if (saving)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final target = def.weeklyTarget;
    final goalMet = weekProgress >= target;

    return Material(
      color: goalMet
          ? cs.tertiaryContainer.withValues(alpha: 0.35)
          : cs.surfaceContainerHighest.withValues(alpha: 0.45),
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Text(
                  '$weekProgress / $target 次',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: goalMet ? cs.tertiary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                if (goalMet) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: '本周目标已达成',
                    child: Icon(
                      Icons.verified_rounded,
                      size: 22,
                      color: cs.tertiary,
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
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: checked
          ? cs.primaryContainer.withValues(alpha: 0.9)
          : cs.surface.withValues(alpha: 0.2),
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: checked ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                checked ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: checked ? cs.primary : cs.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
