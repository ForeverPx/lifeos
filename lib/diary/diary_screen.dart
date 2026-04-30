import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/token_store.dart';
import '../config/github_token.dart';
import '../settings/settings_screen.dart';
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

  Future<void> _loadMonth() async {
    if (!_repo.hasToken) return;
    setState(() {
      _loadingMonth = true;
      _error = null;
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
        _loadingMonth = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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
      _entries = [];
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (kIsWeb) {
      return _WebCorsHint(cs: cs);
    }

    if (_loadingToken) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_repo.hasToken) {
      return _TokenHint(cs: cs, onOpenSettings: _openSettings);
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHighest.withValues(alpha: 0.35),
            cs.primaryContainer.withValues(alpha: 0.25),
            theme.scaffoldBackgroundColor,
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
                            style: GoogleFonts.newsreader(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _openSettings,
                          tooltip: '设置',
                          icon: Icon(
                            Icons.settings_outlined,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ForeverPx / my-ai-memory · daily_notes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
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
                  child: Material(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories_outlined, size: 22, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      _dayLabel(),
                      style: GoogleFonts.newsreader(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    if (_loadingDay) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _EntryCard(entry: _entries[index], cs: cs),
                    );
                  },
                  childCount: _entries.length,
                ),
              ),
            ),
          ],
        ),
      ),
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
  const _WebCorsHint({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.web_asset_outlined, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Web 端限制',
                        style: GoogleFonts.newsreader(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '浏览器无法直接访问 GitHub REST API（跨域策略）。'
                    '请在 iOS、Android 或桌面端运行本应用以同步私有仓库日记；'
                    '若必须在网页中使用，需要自行部署可转发请求的代理服务。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: cs.onSurfaceVariant,
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
  const _TokenHint({required this.cs, required this.onOpenSettings});

  final ColorScheme cs;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        '连接私有仓库',
                        style: GoogleFonts.newsreader(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '日记从 GitHub 私有仓库 '
                    'ForeverPx/my-ai-memory 的 daily_notes 目录读取。'
                    '请使用带 repo 权限的 Personal Access Token，并在设置中填写：',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('打开设置并填写 Token'),
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
    final cs = Theme.of(context).colorScheme;
    final label = DateFormat('yyyy年 MMMM', 'zh_CN').format(visibleMonth);
    return Material(
      elevation: 0,
      color: cs.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
              tooltip: '上月',
            ),
            Expanded(
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : Text(
                        label,
                        style: GoogleFonts.newsreader(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              tooltip: '下月',
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leading = first.weekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Material(
      color: cs.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
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
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
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
                          cs: cs,
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
    required this.cs,
  });

  final int? day;
  final bool Function(int? day) hasEntry;
  final int? selected;
  final ValueChanged<int> onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final d = day;
    if (d == null) {
      return const SizedBox(height: 40);
    }
    final isSelected = selected == d;
    final dot = hasEntry(d);
    return InkWell(
      onTap: () => onTap(d),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? cs.primaryContainer : null,
          border: Border.all(
            color: isSelected ? cs.primary : Colors.transparent,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$d',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dot ? cs.tertiary : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.cs});

  final DiaryEntry entry;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 1.5,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      color: cs.surface,
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
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      entry.timeLabel!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (entry.timeLabel != null) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.title,
                    style: GoogleFonts.newsreader(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              entry.source,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in entry.tags)
                    Chip(
                      label: Text(
                        t,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                      backgroundColor: cs.secondaryContainer.withValues(alpha: 0.65),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
