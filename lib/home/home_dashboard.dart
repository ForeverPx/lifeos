import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../checkin/checkin_models.dart';
import '../checkin/checkin_week.dart';
import '../checkin/github_checkin_repository.dart';
import '../collect/collect_models.dart';
import '../collect/collect_parser.dart';
import '../collect/collect_compose_screen.dart';
import '../collect/github_collect_repository.dart';
import '../config/github_repo_prefs.dart';
import '../config/github_token.dart';
import '../config/token_store.dart';
import '../diary/diary_models.dart';
import '../diary/diary_compose_screen.dart';
import '../diary/github_diary_repository.dart';
import '../settings/settings_screen.dart';

/// Bottom tab index for [LifeOSApp] shell: 1 = 日记, 2 = 收藏, 3 = 打卡.
typedef HomeOpenTab = void Function(int tabIndex);

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key, required this.onOpenTab});

  final HomeOpenTab onOpenTab;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  final _diaryRepo = GithubDiaryRepository();
  final _collectRepo = GithubCollectRepository();
  final _checkinRepo = GithubCheckinRepository();

  bool _loadingToken = true;
  bool _loadingSummary = false;
  String? _summaryError;

  List<DiaryEntry> _diaryToday = const [];
  List<CollectItem> _collectToday = const [];

  /// Calendar day of the diary block shown (null if empty).
  DateTime? _diarySummaryDay;

  /// Calendar day of the collect list shown (null if empty).
  DateTime? _collectSummaryDay;

  WeeklyCheckinState? _checkinState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _loadToken();
    if (!mounted) return;
    if (_diaryRepo.hasToken && !kIsWeb) {
      await _loadSummary();
    }
  }

  Future<void> _loadToken() async {
    final stored = await TokenStore.readGitHubToken();
    final token = stored.trim().isNotEmpty ? stored : GitHubToken.value;
    if (!mounted) return;
    setState(() {
      _loadingToken = false;
      _diaryRepo.setToken(token);
      _collectRepo.setToken(token);
      _checkinRepo.setToken(token);
      if (_diaryRepo.hasToken && !kIsWeb) {
        _loadingSummary = true;
      }
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          onGitHubTokenChanged: () async {
            await _loadToken();
            if (!mounted) return;
            if (_diaryRepo.hasToken && !kIsWeb) {
              await _loadSummary();
            } else {
              setState(() {
                _diaryToday = const [];
                _collectToday = const [];
                _diarySummaryDay = null;
                _collectSummaryDay = null;
                _checkinState = null;
                _summaryError = null;
              });
            }
          },
        ),
      ),
    );
  }

  Future<void> _loadSummary() async {
    if (!_diaryRepo.hasToken || kIsWeb) return;
    setState(() {
      _loadingSummary = true;
      _summaryError = null;
    });
    final today = _today();
    try {
      final diaryFuture = _diaryRepo.fetchDay(
        today.year,
        today.month,
        today.day,
        allowNotFound: true,
      );
      final collectFuture = _loadCollectForDay(today);
      final checkinFuture = _loadCheckinState();
      final results = await Future.wait<dynamic>([
        diaryFuture,
        collectFuture,
        checkinFuture,
      ]);
      if (!mounted) return;

      var diaryEntries = results[0] as List<DiaryEntry>;
      var collectItems = results[1] as List<CollectItem>;
      _checkinState = results[2] as WeeklyCheckinState?;

      DateTime? diaryDay;
      DateTime? collectDay;

      if (diaryEntries.isNotEmpty) {
        diaryDay = today;
      } else {
        final latest = await _latestDiaryDayOnOrBefore(today);
        if (latest != null) {
          diaryEntries = await _diaryRepo.fetchDay(
            latest.year,
            latest.month,
            latest.day,
            allowNotFound: true,
          );
          if (diaryEntries.isNotEmpty) {
            diaryDay = latest;
            diaryEntries = [diaryEntries.last];
          }
        }
      }

      if (collectItems.isNotEmpty) {
        collectDay = today;
      } else {
        final latest = await _latestCollectDayWithFilesOnOrBefore(today);
        if (latest != null) {
          collectItems = await _loadCollectForDay(latest);
          if (collectItems.isNotEmpty) {
            collectDay = latest;
            collectItems = [collectItems.last];
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _diaryToday = diaryEntries;
        _collectToday = collectItems;
        _diarySummaryDay = diaryDay;
        _collectSummaryDay = collectDay;
        _loadingSummary = false;
      });
    } on GithubDiaryException catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = e.message;
        _loadingSummary = false;
      });
    } on GithubCollectException catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = e.message;
        _loadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = e.toString();
        _loadingSummary = false;
      });
    }
  }

  Future<WeeklyCheckinState?> _loadCheckinState() async {
    if (!_checkinRepo.hasToken || kIsWeb) return null;
    try {
      final bounds = CheckinWeekBounds.forLocalDate(_today());
      final snap = await _checkinRepo.fetchWeek(bounds.weekId);
      return snap.state;
    } catch (_) {
      return null;
    }
  }

  /// Latest calendar day ≤ [today] that has a `daily_notes` entry file.
  Future<DateTime?> _latestDiaryDayOnOrBefore(DateTime today) async {
    var cursor = DateTime(today.year, today.month, 1);
    for (var i = 0; i < 36; i++) {
      final y = cursor.year;
      final m = cursor.month;
      final days = await _diaryRepo.listDaysWithEntries(y, m);
      DateTime? best;
      for (final d in days) {
        final dt = DateTime(y, m, d);
        if (dt.isAfter(today)) continue;
        if (best == null || dt.isAfter(best)) best = dt;
      }
      if (best != null) return best;
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }
    return null;
  }

  /// Newest `collect/` day on or before [today] that contains at least one file.
  Future<DateTime?> _latestCollectDayWithFilesOnOrBefore(DateTime today) async {
    final days = await _collectRepo.listDays(limit: 120);
    for (final day in days) {
      if (day.isAfter(today)) continue;
      final files = await _collectRepo.listFilesForDay(day);
      if (files.isNotEmpty) return day;
    }
    return null;
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<List<CollectItem>> _loadCollectForDay(DateTime day) async {
    final files = await _collectRepo.listFilesForDay(day);
    final items = <CollectItem>[];
    final todayOnly = _today();
    final allowCache = day.isBefore(todayOnly);
    for (final f in files) {
      final text = await _collectRepo.fetchFileContent(
        path: f.path,
        sha: f.sha,
        allowCache: allowCache,
      );
      final body = normalizeBody(text);
      final title = titleFromContent(fileName: f.name, content: body);
      items.add(
        CollectItem(
          day: day,
          path: f.path,
          fileName: f.name,
          title: title,
          body: body,
          preview: previewFromBody(body, maxLen: 120),
          tags: tagsFromCollectBody(body),
        ),
      );
    }
    return items;
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了，注意休息';
    if (h < 12) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  bool _isRecentDiaryNotToday(DateTime today) =>
      _diaryToday.isNotEmpty &&
      _diarySummaryDay != null &&
      !_isSameCalendarDay(_diarySummaryDay!, today);

  bool _isRecentCollectNotToday(DateTime today) =>
      _collectToday.isNotEmpty &&
      _collectSummaryDay != null &&
      !_isSameCalendarDay(_collectSummaryDay!, today);

  void _openDiaryPreview(DiaryEntry entry) {
    showFSheet<void>(
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: 0.88,
      builder: (ctx) => ColoredBox(
        color: FTheme.of(ctx).colors.background,
        child: _DiaryEntryPreviewSheet(entry: entry),
      ),
    );
  }

  void _openCollectPreview(CollectItem item) {
    showFSheet<void>(
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: 0.88,
      builder: (ctx) => ColoredBox(
        color: FTheme.of(ctx).colors.background,
        child: _CollectItemPreviewSheet(item: item),
      ),
    );
  }

  Future<void> _openDiaryComposeToday() async {
    final today = _today();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DiaryComposeScreen(
          repo: _diaryRepo,
          year: today.year,
          month: today.month,
          day: today.day,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _loadSummary();
    }
  }

  Future<void> _openCollectComposeToday() async {
    final today = _today();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CollectComposeScreen(
          repo: _collectRepo,
          day: today,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _loadSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (kIsWeb) {
      return const _WebCorsHintBody();
    }

    if (_loadingToken) {
      return const Center(child: FCircularProgress());
    }

    if (!_diaryRepo.hasToken) {
      return _TokenHintBody(onOpenSettings: _openSettings);
    }

    final today = _today();
    final dateLine = DateFormat('M月d日 EEEE', 'zh_CN').format(today);

    return Scaffold(
      backgroundColor: isDark ? colors.background : const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _loadSummary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: colors.primary.withValues(alpha: 0.1),
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
                                    dateLine,
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
                                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
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
                        const SizedBox(height: 8),
                        const _ConnectionChip(),
                        if (_summaryError != null) ...[
                          const SizedBox(height: 12),
                          _ErrorBanner(message: _summaryError!),
                        ],
                        const SizedBox(height: 24),
                        // Diary Card
                        _HomeCard(
                          icon: Icons.menu_book_rounded,
                          iconColor: const Color(0xFF2563EB),
                          iconBgColor: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          title: '日记',
                          badgeColor: const Color(0xFF2563EB),
                          action: _HomeCardAction(
                            label: '新增',
                            icon: Icons.add_rounded,
                            onTap: _openDiaryComposeToday,
                          ),
                          onTap: () {
                            if (_diaryToday.isEmpty) {
                              widget.onOpenTab(1);
                              return;
                            }
                            if (_isRecentDiaryNotToday(today)) {
                              _openDiaryPreview(_diaryToday.first);
                              return;
                            }
                            widget.onOpenTab(1);
                          },
                          child: _DiaryCardContent(
                            entries: _diaryToday,
                            diaryDay: _diarySummaryDay,
                            today: today,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Collect Card
                        _HomeCard(
                          icon: Icons.bookmark_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          iconBgColor: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          title: '收藏',
                          badgeColor: const Color(0xFFF59E0B),
                          action: _HomeCardAction(
                            label: '新增',
                            icon: Icons.add_rounded,
                            onTap: _openCollectComposeToday,
                          ),
                          onTap: () {
                            if (_collectToday.isEmpty) {
                              widget.onOpenTab(2);
                              return;
                            }
                            if (_isRecentCollectNotToday(today)) {
                              _openCollectPreview(_collectToday.first);
                              return;
                            }
                            widget.onOpenTab(2);
                          },
                          child: _CollectCardContent(
                            items: _collectToday,
                            collectDay: _collectSummaryDay,
                            today: today,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Checkin Card
                        _HomeCard(
                          icon: Icons.check_circle_rounded,
                          iconColor: const Color(0xFF10B981),
                          iconBgColor: const Color(0xFF10B981).withValues(alpha: 0.1),
                          title: '打卡',
                          badgeColor: const Color(0xFF10B981),
                          onTap: () => widget.onOpenTab(3),
                          child: _CheckinCardContent(state: _checkinState),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loadingSummary)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: FCircularProgress(
                    size: FCircularProgressSizeVariant.sm,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.badgeColor,
    this.action,
    required this.onTap,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final Color badgeColor;
  final _HomeCardAction? action;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typography = context.theme.typography;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? colors.background : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.foreground,
                    ),
                  ),
                  const Spacer(),
                  if (action != null) ...[
                    _HomeCardActionButton(
                      action: action!,
                      typography: typography,
                      colors: colors,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCardAction {
  const _HomeCardAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _HomeCardActionButton extends StatelessWidget {
  const _HomeCardActionButton({
    required this.action,
    required this.typography,
    required this.colors,
    required this.isDark,
  });

  final _HomeCardAction action;
  final FTypography typography;
  final FColors colors;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: action.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? colors.secondary.withValues(alpha: 0.35) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isDark ? colors.border.withValues(alpha: 0.8) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: 16, color: colors.mutedForeground),
            const SizedBox(width: 6),
            Text(
              action.label,
              style: typography.xs.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiaryCardContent extends StatelessWidget {
  const _DiaryCardContent({
    required this.entries,
    required this.diaryDay,
    required this.today,
  });

  final List<DiaryEntry> entries;
  final DateTime? diaryDay;
  final DateTime today;

  String _subtitle(DiaryEntry e) {
    final parts = <String>[];
    if (e.timeLabel != null && e.timeLabel!.isNotEmpty) {
      parts.add(e.timeLabel!);
    }
    final src = e.source.trim();
    if (src.isNotEmpty) {
      final oneLine = src.replaceAll(RegExp(r'\s+'), ' ');
      parts.add(
        oneLine.length > 48 ? '${oneLine.substring(0, 48)}…' : oneLine,
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    if (entries.isEmpty) {
      return Text(
        '今天还没有日记。点按进入「日记」查看日历或补充记录。',
        style: typography.sm.copyWith(
          color: colors.mutedForeground,
          height: 1.45,
        ),
      );
    }

    final entry = entries.first;
    final isRecent = diaryDay != null &&
        !(diaryDay!.year == today.year && diaryDay!.month == today.month && diaryDay!.day == today.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isRecent && diaryDay != null)
          Text(
            DateFormat('M月d日', 'zh_CN').format(diaryDay!),
            style: typography.sm.copyWith(
              color: const Color(0xFF2563EB),
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            DateFormat('M月d日', 'zh_CN').format(today),
            style: typography.sm.copyWith(
              color: const Color(0xFF2563EB),
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          entry.title.isEmpty ? '未命名' : entry.title,
          style: typography.sm.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (_subtitle(entry).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _subtitle(entry),
            style: typography.xs.copyWith(
              color: colors.mutedForeground,
              height: 1.35,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _CollectCardContent extends StatelessWidget {
  const _CollectCardContent({
    required this.items,
    required this.collectDay,
    required this.today,
  });

  final List<CollectItem> items;
  final DateTime? collectDay;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    if (items.isEmpty) {
      return Text(
        '今天还没有收藏。将 .md / .txt 等放入 collect/ 下的日期文件夹后，点按进入「收藏」下拉同步。',
        style: typography.sm.copyWith(
          color: colors.mutedForeground,
          height: 1.45,
        ),
      );
    }

    final item = items.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: typography.sm.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (item.preview.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            item.preview,
            style: typography.xs.copyWith(
              color: colors.mutedForeground,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '收藏',
                style: typography.xs2.copyWith(
                  color: const Color(0xFFF59E0B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              DateFormat('yyyy年MM月dd日', 'zh_CN').format(collectDay ?? today),
              style: typography.xs2.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CheckinCardContent extends StatelessWidget {
  const _CheckinCardContent({required this.state});

  final WeeklyCheckinState? state;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    if (state == null) {
      return Text(
        '本周习惯完成情况',
        style: typography.sm.copyWith(
          color: colors.mutedForeground,
        ),
      );
    }

    final bounds = CheckinWeekBounds.forLocalDate(DateTime.now());
    final today = DateTime.now();
    final todayYmd = CheckinWeekBounds.ymd(today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '本周习惯完成情况',
          style: typography.sm.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      ['一', '二', '三', '四', '五', '六', '日'][i],
                      style: typography.xs2.copyWith(
                        color: colors.mutedForeground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _WeekDot(
                      checked: _anyCheckedOnDay(bounds.days[i]),
                      isToday: CheckinWeekBounds.ymd(bounds.days[i]) == todayYmd,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  bool _anyCheckedOnDay(DateTime day) {
    if (state == null) return false;
    final ymd = CheckinWeekBounds.ymd(day);
    for (final def in kCheckinProjects) {
      if (state!.isChecked(def.id, ymd)) return true;
    }
    return false;
  }
}

class _WeekDot extends StatelessWidget {
  const _WeekDot({required this.checked, required this.isToday});

  final bool checked;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
        border: isToday && !checked
            ? Border.all(color: const Color(0xFF10B981), width: 2)
            : null,
      ),
      child: checked
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Row(
      children: [
        Icon(Icons.cloud_done_rounded, size: 16, color: colors.primary),
        const SizedBox(width: 6),
        Text(
          'GitHub 已连接',
          style: typography.xs.copyWith(
            color: colors.mutedForeground,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return FAlert(
      variant: FAlertVariant.destructive,
      title: Text(message),
      icon: const Icon(FIcons.circleAlert),
    );
  }
}

MarkdownStyleSheet _homeMarkdownSheet(ThemeData theme, FColors colors, FTypography typography) {
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: typography.sm.copyWith(
      height: 1.55,
      color: colors.mutedForeground,
    ),
    h1: typography.xl.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.foreground,
      height: 1.2,
    ),
    h2: typography.lg.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.foreground,
      height: 1.2,
    ),
    h3: typography.md.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.foreground,
      height: 1.2,
    ),
    code: typography.sm.copyWith(
      fontFamily: 'monospace',
      color: colors.foreground,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: colors.secondary.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: colors.border),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    blockquoteDecoration: BoxDecoration(
      color: colors.secondary.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      border: Border(
        left: BorderSide(
          color: colors.primary.withValues(alpha: 0.85),
          width: 3,
        ),
      ),
    ),
    a: typography.sm.copyWith(
      color: colors.primary,
      decoration: TextDecoration.underline,
    ),
  );
}

class _DiaryEntryPreviewSheet extends StatelessWidget {
  const _DiaryEntryPreviewSheet({required this.entry});

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final bodyMd = entry.source.trim();

    return ColoredBox(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.title.isEmpty ? '未命名' : entry.title,
                    style: typography.xl.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                      height: 1.2,
                    ),
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Icon(FIcons.x),
                ),
              ],
            ),
          ),
          if (entry.headerLine.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                entry.headerLine,
                style: typography.xs.copyWith(
                  color: colors.mutedForeground,
                  height: 1.35,
                ),
              ),
            ),
          if (entry.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: entry.tags
                    .map(
                      (t) => FBadge(
                        variant: FBadgeVariant.outline,
                        child: Text(t, style: typography.xs2),
                      ),
                    )
                    .toList(),
              ),
            ),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: bodyMd.isEmpty
                    ? Text(
                        '（暂无 source 正文）',
                        style: typography.sm.copyWith(
                          height: 1.55,
                          color: colors.mutedForeground,
                        ),
                      )
                    : MarkdownBody(
                        data: bodyMd,
                        styleSheet: _homeMarkdownSheet(theme, colors, typography),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectItemPreviewSheet extends StatelessWidget {
  const _CollectItemPreviewSheet({required this.item});

  final CollectItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    return ColoredBox(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: typography.xl.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                      height: 1.2,
                    ),
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Icon(FIcons.x),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              item.path,
              style: typography.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: item.body.trim().isEmpty
                    ? Text(
                        '（内容为空）',
                        style: typography.sm.copyWith(
                          height: 1.55,
                          color: colors.mutedForeground,
                        ),
                      )
                    : MarkdownBody(
                        data: item.body,
                        styleSheet: _homeMarkdownSheet(theme, colors, typography),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenHintBody extends StatelessWidget {
  const _TokenHintBody({required this.onOpenSettings});

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
                    'LifeOS 从 GitHub 私有库 ${GitHubRepoPrefs.displayName} 读取首页摘要、日记与收藏。'
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

class _WebCorsHintBody extends StatelessWidget {
  const _WebCorsHintBody();

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
