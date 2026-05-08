import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../config/github_raw_url.dart';
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
        builder: (_) =>
            SettingsScreen(onGitHubTokenChanged: _loadTokenAndRefresh),
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
            _daysWithEntries.isNotEmpty &&
            !_daysWithEntries.contains(_selectedDay!),
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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了，注意休息';
    if (h < 12) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const diaryAccent = Color(0xFF2563EB);

    if (kIsWeb) {
      return const _WebCorsHint();
    }

    if (_loadingToken) {
      return const Center(child: FCircularProgress());
    }

    if (!_repo.hasToken) {
      return _TokenHint(onOpenSettings: _openSettings);
    }

    final today = DateTime.now();
    final dateLine = DateFormat('M月d日 EEEE', 'zh_CN').format(today);

    return Scaffold(
      backgroundColor: isDark ? colors.background : const Color(0xFFF5F7FA),
      floatingActionButton: _selectedDay == null
          ? null
          : FloatingActionButton(
              onPressed: _openCompose,
              backgroundColor: diaryAccent,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadMonth();
            await _loadSelectedDay();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'LifeOS',
                                      style: typography.xl.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colors.foreground,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'v1.0',
                                        style: typography.sm.copyWith(
                                          color: colors.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '$dateLine · ${GitHubRepoPrefs.displayName} · daily_notes',
                                  style: typography.sm.copyWith(
                                    color: colors.mutedForeground,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _greeting(),
                                  style: typography.lg.copyWith(
                                    color: colors.foreground,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _openSettings,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isDark ? colors.secondary : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.2 : 0.04,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.settings_outlined,
                                size: 20,
                                color: colors.mutedForeground,
                              ),
                            ),
                          ),
                        ],
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
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: diaryAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          size: 16,
                          color: diaryAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _dayLabel(),
                          style: typography.md.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.foreground,
                          ),
                        ),
                      ),
                      if (_loadingDay)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        ),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _EntryCard(
                        entry: _entries[index],
                        imageToken: _repo.token,
                        onDelete: () => _deleteEntry(_entries[index]),
                      ),
                    );
                  }, childCount: _entries.length),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dayLabel() {
    if (_selectedDay == null) return '选择日期';
    final d = DateTime(_visibleMonth.year, _visibleMonth.month, _selectedDay!);
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
          child: _DiarySurfaceCard(
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
          child: _DiarySurfaceCard(
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
                  GestureDetector(
                    onTap: onOpenSettings,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FIcons.settings,
                            size: 16,
                            color: colors.primaryForeground,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '前往设置',
                            style: typography.sm.copyWith(
                              color: colors.primaryForeground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
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
    return _DiarySurfaceCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            GestureDetector(
              onTap: onPrev,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(FIcons.chevronLeft, color: colors.foreground),
              ),
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
            GestureDetector(
              onTap: onNext,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(FIcons.chevronRight, color: colors.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Surface card style aligned with [CollectScreen] / home dashboard.
class _DiarySurfaceCard extends StatelessWidget {
  const _DiarySurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.background : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
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
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final leading = first.weekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return _DiarySurfaceCard(
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
            color: isSelected ? colors.primary : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$d',
                style: typography.sm.copyWith(
                  color: isSelected
                      ? colors.primaryForeground
                      : colors.foreground,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot
                      ? (isSelected ? colors.primaryForeground : colors.primary)
                      : Colors.transparent,
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
    required this.imageToken,
    required this.onDelete,
  });

  final DiaryEntry entry;
  final String imageToken;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final theme = Theme.of(context);
    return _DiarySurfaceCard(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
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
                GestureDetector(
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      FIcons.trash2,
                      size: 20,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectionArea(
              child: entry.source.trim().isEmpty
                  ? Text(
                      '（内容为空）',
                      style: typography.sm.copyWith(
                        height: 1.55,
                        color: colors.mutedForeground,
                      ),
                    )
                  : MarkdownBody(
                      data: entry.source,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: typography.sm.copyWith(
                          height: 1.55,
                          color: colors.mutedForeground,
                        ),
                        a: typography.sm.copyWith(color: colors.primary),
                      ),
                      imageBuilder: (uri, title, alt) {
                        final image = githubImageRequest(
                          uri.toString(),
                          token: imageToken,
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              image.url,
                              headers: image.headers,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  height: 180,
                                  alignment: Alignment.center,
                                  color: colors.secondary,
                                  child: const FCircularProgress(
                                    size: FCircularProgressSizeVariant.sm,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colors.secondary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '图片加载失败：$error',
                                    style: typography.xs.copyWith(
                                      color: colors.mutedForeground,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
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
