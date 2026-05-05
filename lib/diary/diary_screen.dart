import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../config/github_repo_prefs.dart';
import '../config/github_token.dart';
import '../config/token_store.dart';
import '../settings/settings_screen.dart';
import 'diary_compose_screen.dart';
import 'diary_models.dart';
import 'github_diary_repository.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final _repo = GithubDiaryRepository();
  bool _loadingToken = true;

  late DateTime _visibleMonth;
  int? _selectedDay;

  Set<int> _daysWithEntries = {};
  List<DiaryEntry> _entries = [];
  bool _loadingMonth = false;
  bool _loadingDay = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _visibleMonth = DateTime(n.year, n.month);
    _selectedDay = n.day;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTokenAndRefresh();
    });
  }

  Future<void> _loadTokenAndRefresh() async {
    final stored = await TokenStore.readGitHubToken();
    final token = stored.trim().isNotEmpty ? stored : GitHubToken.value;
    if (!mounted) return;
    setState(() {
      _loadingToken = false;
      _repo.setToken(token);
    });
    await _loadMonth();
    await _loadSelectedDay();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          onGitHubTokenChanged: _loadTokenAndRefresh,
        ),
      ),
    );
    await _loadTokenAndRefresh();
  }

  Future<void> _deleteEntry(DiaryEntry entry) async {
    if (_selectedDay == null) return;
    final ok = await showFDialog<bool>(
      context: context,
      builder: (ctx, style, animation) => FDialog(
        title: const Text('删除这条日记？'),
        body: Text('将永久从 GitHub 仓库移除该条记录：\n${entry.title}'),
        actions: [
          FButton(
            onPress: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _loadingDay = true;
      _error = null;
    });
    try {
      await _repo.removeDiaryEntry(
        year: _visibleMonth.year,
        month: _visibleMonth.month,
        day: _selectedDay!,
        headerLine: entry.headerLine,
      );
      if (!mounted) return;
      showFToast(
        context: context,
        icon: const Icon(FIcons.trash2),
        title: const Text('已删除'),
      );
      await _loadMonth();
      await _loadSelectedDay();
    } on GithubDiaryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingDay = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingDay = false;
      });
    }
  }

  Future<void> _openCompose() async {
    if (_selectedDay == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DiaryComposeScreen(
          repo: _repo,
          year: _visibleMonth.year,
          month: _visibleMonth.month,
          day: _selectedDay!,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _loadMonth();
      await _loadSelectedDay();
    }
  }

  Future<void> _loadMonth() async {
    if (!_repo.hasToken) return;
    setState(() {
      _loadingMonth = true;
      _error = null;
      _daysWithEntries = {};
    });
    try {
      final days = await _repo.listDaysWithEntries(
        _visibleMonth.year,
        _visibleMonth.month,
      );
      if (!mounted) return;
      setState(() {
        _daysWithEntries = days;
        _loadingMonth = false;
      });
    } on GithubDiaryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _daysWithEntries = {};
        _loadingMonth = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _daysWithEntries = {};
        _loadingMonth = false;
      });
    }
  }

  Future<void> _loadSelectedDay() async {
    if (!_repo.hasToken || _selectedDay == null) return;
    setState(() {
      _loadingDay = true;
      _error = null;
    });
    try {
      final list = await _repo.fetchDay(
        _visibleMonth.year,
        _visibleMonth.month,
        _selectedDay!,
        assumeExists: _daysWithEntries.contains(_selectedDay!),
        allowNotFound:
            _daysWithEntries.isNotEmpty && !_daysWithEntries.contains(_selectedDay!),
      );
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loadingDay = false;
      });
    } on GithubDiaryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _entries = [];
        _loadingDay = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _entries = [];
        _loadingDay = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    final d = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    setState(() {
      _visibleMonth = d;
      _selectedDay = null;
      _daysWithEntries = {};
      _entries = [];
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    if (kIsWeb) {
      return const _WebCorsHint();
    }

    if (_loadingToken) {
      return const Center(child: FCircularProgress());
    }

    if (!_repo.hasToken) {
      return _TokenHint(onOpenSettings: _openSettings);
    }

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.secondary.withValues(alpha: 0.45),
                colors.primary.withValues(alpha: 0.08),
                colors.background,
              ],
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '日记',
                            style: typography.xl.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.foreground,
                              height: 1.1,
                            ),
                          ),
                        ),
                        FButton.icon(
                          variant: FButtonVariant.ghost,
                          onPress: _openSettings,
                          child: Icon(
                            FIcons.settings,
                            color: colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                      Text(
                        '${GitHubRepoPrefs.displayName} · 日记 daily_notes',
                        style: typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _MonthHeader(
                  visibleMonth: _visibleMonth,
                  onPrev: () => _shiftMonth(-1),
                  onNext: () => _shiftMonth(1),
                  loading: _loadingMonth,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _CalendarCard(
                  visibleMonth: _visibleMonth,
                  daysWithEntries: _daysWithEntries,
                  selectedDay: _selectedDay,
                  onSelectDay: (day) {
                    setState(() => _selectedDay = day);
                    _loadSelectedDay();
                  },
                ),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FAlert(
                    variant: FAlertVariant.destructive,
                    title: Text(_error!),
                    icon: const Icon(FIcons.circleAlert),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Icon(FIcons.bookOpenText, size: 22, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      _dayLabel(),
                      style: typography.xl.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.foreground,
                        height: 1.2,
                      ),
                    ),
                    if (_loadingDay) ...[
                      const SizedBox(width: 12),
                      const FCircularProgress(
                        size: FCircularProgressSizeVariant.sm,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_entries.isEmpty && !_loadingDay && _selectedDay != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '这一天还没有记录，或文件为空。',
                    style: typography.sm.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
              ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _EntryCard(
                            entry: _entries[index],
                            onDelete: () => _deleteEntry(_entries[index]),
                          ),
                        );
                      },
                      childCount: _entries.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_selectedDay != null)
          Positioned(
            right: 20,
            bottom: 20,
            child: FButton(
              onPress: _openCompose,
              prefix: const Icon(FIcons.pencil),
              child: const Text('新增日记'),
            ),
          ),
      ],
    );
  }

  String _dayLabel() {
    if (_selectedDay == null) return '选择日期';
    final d = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      _selectedDay!,
    );
    return DateFormat('yyyy年MM月dd日 EEEE', 'zh_CN').format(d);
  }
}

class _WebCorsHint extends StatelessWidget {
  const _WebCorsHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: FCard.raw(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(FIcons.globe, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Web 端限制',
                        style: typography.xl.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.foreground,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '受浏览器 CORS 限制，本应用无法在网页内直接请求 GitHub。'
                    '请在 iOS、Android 或桌面端使用；若必须在浏览器中使用，需自行搭建可转发的 API 代理。',
                    style: typography.sm.copyWith(
                      height: 1.45,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenHint extends StatelessWidget {
  const _TokenHint({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: FCard.raw(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(FIcons.lock, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '连接私有仓库',
                        style: typography.xl.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.foreground,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '日记读取自 ${GitHubRepoPrefs.displayName} 仓库中的 daily_notes 目录。'
                    '请使用具备 repo 权限的 Personal Access Token（PAT），在设置中粘贴保存。',
                    style: typography.sm.copyWith(
                      height: 1.45,
                      color: colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FButton(
                    onPress: onOpenSettings,
                    prefix: const Icon(FIcons.settings),
                    child: const Text('前往设置'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.visibleMonth,
    required this.onPrev,
    required this.onNext,
    required this.loading,
  });

  final DateTime visibleMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final label = DateFormat('yyyy年 MMMM', 'zh_CN').format(visibleMonth);
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: onPrev,
              child: const Icon(FIcons.chevronLeft),
            ),
            Expanded(
              child: Center(
                child: loading
                    ? const FCircularProgress(
                        size: FCircularProgressSizeVariant.sm,
                      )
                    : Text(
                        label,
                        style: typography.xl.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.foreground,
                          height: 1.2,
                        ),
                      ),
              ),
            ),
            FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: onNext,
              child: const Icon(FIcons.chevronRight),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.visibleMonth,
    required this.daysWithEntries,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final DateTime visibleMonth;
  final Set<int> daysWithEntries;
  final int? selectedDay;
  final ValueChanged<int> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leading = first.weekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          children: [
            Row(
              children: [
                for (final w in weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: typography.xs2.copyWith(
                          color: colors.mutedForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var row = 0; row < totalCells ~/ 7; row++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _DayCell(
                          day: _cellDay(
                            row: row,
                            col: col,
                            leading: leading,
                            daysInMonth: daysInMonth,
                          ),
                          hasEntry: (day) =>
                              day != null && daysWithEntries.contains(day),
                          selected: selectedDay,
                          onTap: onSelectDay,
                          colors: colors,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  int? _cellDay({
    required int row,
    required int col,
    required int leading,
    required int daysInMonth,
  }) {
    final index = row * 7 + col;
    final dayNum = index - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) return null;
    return dayNum;
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.hasEntry,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final int? day;
  final bool Function(int? day) hasEntry;
  final int? selected;
  final ValueChanged<int> onTap;
  final FColors colors;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final d = day;
    if (d == null) {
      return const SizedBox(height: 40);
    }
    final isSelected = selected == d;
    final dot = hasEntry(d);
    // InkWell must sit under a Material (FCard.raw does not provide one).
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onTap(d),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected ? colors.secondary : null,
            border: Border.all(
              color: isSelected ? colors.primary : Colors.transparent,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$d',
                style: typography.sm.copyWith(
                  color: isSelected ? colors.primary : colors.foreground,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot ? colors.primary : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.onDelete,
  });

  final DiaryEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.timeLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      entry.timeLabel!,
                      style: typography.xs.copyWith(
                        color: colors.secondaryForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (entry.timeLabel != null) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.title,
                    style: typography.xl.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: colors.foreground,
                    ),
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: onDelete,
                  child: Icon(
                    FIcons.trash2,
                    size: 20,
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              entry.source,
              style: typography.sm.copyWith(
                height: 1.5,
                color: colors.mutedForeground,
              ),
            ),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in entry.tags)
                    FBadge(
                      variant: FBadgeVariant.secondary,
                      child: Text(t, style: typography.xs2),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
