import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../config/github_repo_prefs.dart';
import '../config/github_token.dart';
import '../config/token_store.dart';
import '../settings/settings_screen.dart';
import 'checkin_global_stats.dart';
import 'checkin_models.dart';
import 'checkin_week.dart';
import 'checkin_week_calendar.dart';
import 'checkin_week_panel.dart';
import 'github_checkin_repository.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _repo = GithubCheckinRepository();
  bool _loadingToken = true;

  bool _loadingWeek = false;
  WeeklyCheckinState? _state;
  String? _fileSha;
  String? _loadError;
  bool _saving = false;

  CheckinGlobalStatsDocument _globalStats = CheckinGlobalStatsDocument.empty();
  String? _statsError;

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<CheckinGlobalStatsDocument> _backfillRecentWeekRollupsIfMissing({
    required DateTime today,
    required CheckinGlobalStatsDocument globalStats,
    WeeklyCheckinState? currentWeekLiveState,
  }) async {
    final bounds = CheckinWeekBounds.forLocalDate(today);
    final recent = CheckinWeekBounds.lastNWeeksNewestFirst(today, 12);

    final missing = <String>[];
    for (final w in recent) {
      if (w.weekId == bounds.weekId) continue; // current week already has live state
      if (!globalStats.weeks.containsKey(w.weekId)) missing.add(w.weekId);
    }
    if (missing.isEmpty) return globalStats;

    final rollups = <String, CheckinWeekRollup>{};
    for (final id in missing) {
      final b = CheckinWeekBounds.tryParseWeekId(id);
      if (b == null) continue;
      try {
        final snap = await _repo.fetchWeek(id);
        // If the file is missing (404), repo returns empty state; keep it as "missing stats".
        if (snap.fileSha == null) continue;
        rollups[id] = CheckinWeekRollup.fromState(snap.state, b);
      } catch (_) {
        // Ignore backfill failures; calendar will show "暂无统计".
      }
    }

    if (rollups.isEmpty) return globalStats;
    var next = globalStats;
    for (final r in rollups.values) {
      next = next.upsertWeek(r);
    }
    return next;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTokenAndRefresh());
  }

  Future<void> _loadTokenAndRefresh() async {
    final stored = await TokenStore.readGitHubToken();
    final token = stored.trim().isNotEmpty ? stored : GitHubToken.value;
    if (!mounted) return;
    setState(() {
      _loadingToken = false;
      _repo.setToken(token);
    });
    await _refreshWeek();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          onGitHubTokenChanged: _loadTokenAndRefresh,
        ),
      ),
    );
    await _loadTokenAndRefresh();
  }

  Future<void> _refreshWeek() async {
    if (!_repo.hasToken || kIsWeb) return;
    final today = _today();
    final bounds = CheckinWeekBounds.forLocalDate(today);
    setState(() {
      _loadingWeek = true;
      _loadError = null;
    });
    try {
      final weekFuture = _repo.fetchWeek(bounds.weekId);
      final statsFuture = _repo.fetchGlobalStats();
      final weekSnap = await weekFuture;
      CheckinGlobalStatsSnapshot statsSnap;
      String? statsLoadErr;
      try {
        statsSnap = await statsFuture;
      } catch (e) {
        statsSnap = CheckinGlobalStatsSnapshot(
          document: CheckinGlobalStatsDocument.empty(),
          fileSha: null,
        );
        statsLoadErr = e.toString();
      }

      final mergedStats = await _backfillRecentWeekRollupsIfMissing(
        today: today,
        globalStats: statsSnap.document,
        currentWeekLiveState: weekSnap.state,
      );

      if (!mounted) return;
      setState(() {
        _state = weekSnap.state;
        _fileSha = weekSnap.fileSha;
        _globalStats = mergedStats;
        _statsError = statsLoadErr;
        _loadingWeek = false;
        _loadError = null;
      });
    } on GithubCheckinException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = WeeklyCheckinState.empty(bounds.weekId);
        _fileSha = null;
        _loadError = e.message;
        _loadingWeek = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = WeeklyCheckinState.empty(bounds.weekId);
        _fileSha = null;
        _loadError = e.toString();
        _loadingWeek = false;
      });
    }
  }

  Future<void> _toggle(String projectId, String ymd) async {
    if (_saving || _state == null || kIsWeb) return;
    final today = _today();
    final bounds = CheckinWeekBounds.forLocalDate(today);
    if (_state!.weekId != bounds.weekId) {
      await _refreshWeek();
      return;
    }
    final previousState = _state!.copy();
    final previousSha = _fileSha;
    final next = previousState.toggle(projectId, ymd);
    setState(() {
      _state = next;
      _saving = true;
      _loadError = null;
    });
    try {
      final outcome = await _repo.saveWeek(
        weekId: bounds.weekId,
        state: next,
        previousSha: previousSha,
      );
      if (!mounted) return;
      setState(() {
        _fileSha = outcome.weekFileSha;
        if (outcome.globalStatsUpdated && outcome.globalStatsDocument != null) {
          // Merge the server's response INTO the existing _globalStats so that
          // weeks already loaded (including client-side backfilled ones like W18)
          // are never dropped when the server returns a document that only contains
          // the just-saved week.
          var merged = _globalStats;
          for (final entry in outcome.globalStatsDocument!.weeks.entries) {
            merged = merged.upsertWeek(entry.value);
          }
          _globalStats = merged;
          _statsError = null;
        } else if (!outcome.globalStatsUpdated) {
          _statsError = outcome.globalStatsError;
        }
        _saving = false;
      });

      if (!outcome.globalStatsUpdated &&
          outcome.globalStatsError != null &&
          mounted) {
        showFToast(
          context: context,
          title: const Text('周打卡已保存'),
          description: Text('全局统计未同步：${outcome.globalStatsError}'),
        );
      }
    } on GithubCheckinException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = previousState;
        _fileSha = previousSha;
        _saving = false;
      });
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: Text('打卡同步失败：${e.message}'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = previousState;
        _fileSha = previousSha;
        _saving = false;
      });
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: Text('打卡同步失败：$e'),
      );
    }
  }

  Future<void> _openWeekDetail(CheckinWeekBounds bounds) async {
    showFSheet<void>(
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: 0.9,
      builder: (ctx) => ColoredBox(
        color: FTheme.of(ctx).colors.background,
        child: _WeekDetailSheet(repo: _repo, bounds: bounds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (kIsWeb) {
      return const _WebHint();
    }

    if (_loadingToken) {
      return const Center(child: FCircularProgress());
    }

    if (!_repo.hasToken) {
      return _TokenHint(onOpenSettings: _openSettings);
    }

    final today = _today();
    final bounds = CheckinWeekBounds.forLocalDate(today);

    return Scaffold(
      backgroundColor: isDark ? colors.background : const Color(0xFFF5F7FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshWeek,
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
                        children: [
                          Expanded(
                            child: Text(
                              '打卡',
                              style: typography.xl.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.foreground,
                                height: 1.1,
                              ),
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
                      const SizedBox(height: 4),
                      Text(
                        '${GitHubRepoPrefs.displayName} · 按周打卡',
                        style: typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                      if (_statsError != null) ...[
                        const SizedBox(height: 12),
                        FAlert(
                          variant: FAlertVariant.destructive,
                          title: const Text('统计汇总加载失败'),
                          icon: const Icon(FIcons.circleAlert),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _statsError!,
                          style: typography.xs.copyWith(
                            color: colors.error,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (_loadError != null) ...[
                        const SizedBox(height: 12),
                        FAlert(
                          variant: FAlertVariant.destructive,
                          title: Text(_loadError!),
                          icon: const Icon(FIcons.circleAlert),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _SectionCard(
                        child: CheckinWeekPanel(
                          bounds: bounds,
                          state: _state ?? WeeklyCheckinState.empty(bounds.weekId),
                          loading: _loadingWeek && _state == null,
                          saving: _saving,
                          showHeading: true,
                          onToggle: _toggle,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        child: CheckinRecentWeeksCalendar(
                          weeks: CheckinWeekBounds.lastNWeeksNewestFirst(today, 12),
                          statsByWeekId: _globalStats.weeks,
                          currentWeekId: bounds.weekId,
                          currentWeekLiveState: _state,
                          loading: _loadingWeek,
                          onOpenWeek: _openWeekDetail,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
        child: child,
      ),
    );
  }
}

class _WeekDetailSheet extends StatefulWidget {
  const _WeekDetailSheet({required this.repo, required this.bounds});

  final GithubCheckinRepository repo;
  final CheckinWeekBounds bounds;

  @override
  State<_WeekDetailSheet> createState() => _WeekDetailSheetState();
}

class _WeekDetailSheetState extends State<_WeekDetailSheet> {
  bool _loading = true;
  WeeklyCheckinState? _state;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await widget.repo.fetchWeek(widget.bounds.weekId);
      if (!mounted) return;
      setState(() {
        _state = snap.state;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '周详情',
                    style: typography.lg.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.foreground,
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
            const SizedBox(height: 10),
            if (_error != null) ...[
              FAlert(
                variant: FAlertVariant.destructive,
                title: Text('加载失败：$_error'),
                icon: const Icon(FIcons.circleAlert),
              ),
              const SizedBox(height: 12),
              FButton(
                onPress: _load,
                prefix: const Icon(FIcons.rotateCw),
                child: const Text('重试'),
              ),
            ] else ...[
              CheckinWeekPanel(
                bounds: widget.bounds,
                state: _state ?? WeeklyCheckinState.empty(widget.bounds.weekId),
                loading: _loading,
                saving: false,
                showHeading: true,
                onToggle: (projectId, ymd) {},
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WebHint extends StatelessWidget {
  const _WebHint();

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
                    '打卡按周写入 ${GitHubRepoPrefs.displayName} 仓库中的 checkins 目录；'
                    '保存时会同步周统计汇总。请使用具备 repo 权限的 Personal Access Token（PAT），在设置中粘贴保存。',
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
