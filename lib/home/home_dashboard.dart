import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../collect/collect_models.dart';
import '../collect/collect_parser.dart';
import '../collect/github_collect_repository.dart';
import '../config/github_token.dart';
import '../config/token_store.dart';
import '../diary/diary_models.dart';
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

  bool _loadingToken = true;
  bool _loadingSummary = false;
  String? _summaryError;

  List<DiaryEntry> _diaryToday = const [];
  List<CollectItem> _collectToday = const [];

  /// Calendar day of the diary block shown (null if empty).
  DateTime? _diarySummaryDay;

  /// Calendar day of the collect list shown (null if empty).
  DateTime? _collectSummaryDay;

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
      final pair = await Future.wait<Object>([
        diaryFuture,
        collectFuture,
      ]);
      if (!mounted) return;

      var diaryEntries = pair[0] as List<DiaryEntry>;
      var collectItems = pair[1] as List<CollectItem>;
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

  String _diarySectionLabel(DateTime today) {
    if (_diaryToday.isEmpty) return '今日日记';
    if (_diarySummaryDay != null && !_isSameCalendarDay(_diarySummaryDay!, today)) {
      return '最近日记';
    }
    return '今日日记';
  }

  String? _diarySectionCaption(DateTime today) {
    if (_diaryToday.isEmpty) return null;
    if (_diarySummaryDay != null && !_isSameCalendarDay(_diarySummaryDay!, today)) {
      return '今天暂无记录，以下为 ${DateFormat('y年M月d日', 'zh_CN').format(_diarySummaryDay!)} 最近一条';
    }
    return null;
  }

  String _collectSectionLabel(DateTime today) {
    if (_collectToday.isEmpty) return '今日收藏';
    if (_collectSummaryDay != null && !_isSameCalendarDay(_collectSummaryDay!, today)) {
      return '最近收藏';
    }
    return '今日收藏';
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

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    if (kIsWeb) {
      return const _DecoratedShell(
        child: _WebCorsHintBody(),
      );
    }

    if (_loadingToken) {
      return const _DecoratedShell(
        child: Center(child: FCircularProgress()),
      );
    }

    if (!_diaryRepo.hasToken) {
      return _DecoratedShell(
        child: _TokenHintBody(onOpenSettings: _openSettings),
      );
    }

    final today = _today();
    final dateLine = DateFormat('y年M月d日 EEEE', 'zh_CN').format(today);

    return _DecoratedShell(
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
                                  Text(
                                    'LifeOS',
                                    style: typography.xl2.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colors.foreground,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dateLine,
                                    style: typography.sm.copyWith(
                                      color: colors.mutedForeground,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _greeting(),
                                    style: typography.md.copyWith(
                                      color: colors.foreground,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
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
                        const SizedBox(height: 12),
                        const _ConnectionChip(),
                        if (_summaryError != null) ...[
                          const SizedBox(height: 12),
                          _ErrorBanner(message: _summaryError!),
                        ],
                        const SizedBox(height: 20),
                        _SectionTitle(
                          icon: FIcons.bookOpenText,
                          label: _diarySectionLabel(today),
                          caption: _diarySectionCaption(today),
                        ),
                        const SizedBox(height: 10),
                        _DiaryTodayCard(
                          entries: _diaryToday,
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
                        ),
                        const SizedBox(height: 20),
                        _SectionTitle(
                          icon: FIcons.bookmark,
                          label: _collectSectionLabel(today),
                        ),
                        const SizedBox(height: 10),
                        _CollectTodayCard(
                          items: _collectToday,
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
                        ),
                        const SizedBox(height: 28),
                        Text(
                          '快捷入口',
                          style: typography.sm.copyWith(
                            color: colors.mutedForeground,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FButton(
                                onPress: () => widget.onOpenTab(1),
                                prefix: const Icon(FIcons.pencil),
                                child: const Text('日记'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FButton(
                                variant: FButtonVariant.outline,
                                onPress: () => widget.onOpenTab(2),
                                prefix: const Icon(FIcons.bookmark),
                                child: const Text('收藏'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FButton(
                            variant: FButtonVariant.ghost,
                            onPress: _openSettings,
                            prefix: Icon(FIcons.slidersHorizontal, size: 20, color: colors.primary),
                            child: Text('GitHub 与缓存设置', style: TextStyle(color: colors.primary)),
                          ),
                        ),
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
    );
  }
}

class _DecoratedShell extends StatelessWidget {
  const _DecoratedShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.12),
            colors.background,
          ],
        ),
      ),
      child: SafeArea(child: child),
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
        Icon(FIcons.cloudCheck, size: 18, color: colors.primary),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.label,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: typography.xl.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.foreground,
                height: 1.2,
              ),
            ),
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            style: typography.xs.copyWith(
              color: colors.mutedForeground,
              height: 1.4,
            ),
          ),
        ],
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

class _DiaryTodayCard extends StatelessWidget {
  const _DiaryTodayCard({
    required this.entries,
    required this.onTap,
  });

  final List<DiaryEntry> entries;
  final VoidCallback onTap;

  String _subtitle(DiaryEntry e) {
    final parts = <String>[];
    if (e.timeLabel != null && e.timeLabel!.isNotEmpty) {
      parts.add(e.timeLabel!);
    }
    final src = e.source.trim();
    if (src.isNotEmpty) {
      final oneLine = src.replaceAll(RegExp(r'\s+'), ' ');
      parts.add(
        oneLine.length > 72 ? '${oneLine.substring(0, 72)}…' : oneLine,
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return FCard.raw(
      child: FTappable.static(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: entries.isEmpty
              ? Text(
                  '今天还没有日记条目。点按前往日历选择日期或新建记录。',
                  style: typography.sm.copyWith(
                    color: colors.mutedForeground,
                    height: 1.45,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < entries.length && i < 4; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      Text(
                        entries[i].title.isEmpty ? '未命名' : entries[i].title,
                        style: typography.sm.copyWith(
                          color: colors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_subtitle(entries[i]).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _subtitle(entries[i]),
                          style: typography.xs.copyWith(
                            color: colors.mutedForeground,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                    if (entries.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '还有 ${entries.length - 4} 条…',
                          style: typography.xs2.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CollectTodayCard extends StatelessWidget {
  const _CollectTodayCard({
    required this.items,
    required this.onTap,
  });

  final List<CollectItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final show = items.take(3).toList();
    return FCard.raw(
      child: FTappable.static(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: items.isEmpty
              ? Text(
                  '今天还没有收藏。在仓库 collect/ 对应日期目录下添加条目后会显示在这里。',
                  style: typography.sm.copyWith(
                    color: colors.mutedForeground,
                    height: 1.45,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < show.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      Text(
                        show[i].title,
                        style: typography.sm.copyWith(
                          color: colors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (show[i].preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          show[i].preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: typography.xs.copyWith(
                            color: colors.mutedForeground,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

MarkdownStyleSheet _homeMarkdownSheet(ThemeData theme, FColors colors, FTypography typography) {
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: typography.sm.copyWith(
      height: 1.55,
      color: colors.mutedForeground,
    ),
    h1: typography.xl2.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.foreground,
      height: 1.2,
    ),
    h2: typography.xl.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.foreground,
      height: 1.2,
    ),
    h3: typography.lg.copyWith(
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
                    '首页摘要、日记与收藏都从 GitHub 私有仓库 ForeverPx/my-ai-memory 读取。'
                    '请使用带 repo 权限的 Personal Access Token，并在设置中填写。',
                    style: typography.sm.copyWith(
                      height: 1.45,
                      color: colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FButton(
                    onPress: onOpenSettings,
                    prefix: const Icon(FIcons.settings),
                    child: const Text('打开设置并填写 Token'),
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
                    '浏览器无法直接访问 GitHub REST API（跨域策略）。'
                    '请在 iOS、Android 或桌面端运行本应用以同步私有仓库；'
                    '若必须在网页中使用，需要自行部署可转发请求的代理服务。',
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
