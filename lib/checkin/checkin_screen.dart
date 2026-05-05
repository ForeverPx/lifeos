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

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _refreshWeek() async {
    if (!_repo.hasToken || kIsWeb) return;
    final bounds = CheckinWeekBounds.forLocalDate(_today());
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
      if (!mounted) return;
      setState(() {
        _state = weekSnap.state;
        _fileSha = weekSnap.fileSha;
        _globalStats = statsSnap.document;
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
    final bounds = CheckinWeekBounds.forLocalDate(_today());
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
          _globalStats = outcome.globalStatsDocument!;
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

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

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

    return Container(
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
                        '${GitHubRepoPrefs.displayName} · 打卡（按周）',
                        style: typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                      if (_statsError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '统计汇总加载失败：$_statsError',
                          style: typography.xs.copyWith(
                            color: colors.error,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (_loadError != null) ...[
                        const SizedBox(height: 14),
                        FAlert(
                          variant: FAlertVariant.destructive,
                          title: Text(_loadError!),
                          icon: const Icon(FIcons.circleAlert),
                        ),
                      ],
                      const SizedBox(height: 20),
                      CheckinWeekPanel(
                        bounds: bounds,
                        state: _state ??
                            WeeklyCheckinState.empty(bounds.weekId),
                        loading: _loadingWeek && _state == null,
                        saving: _saving,
                        showHeading: false,
                        onToggle: _toggle,
                      ),
                      const SizedBox(height: 28),
                      CheckinRecentWeeksCalendar(
                        weeks: CheckinWeekBounds.lastNWeeksNewestFirst(today, 12),
                        statsByWeekId: _globalStats.weeks,
                        currentWeekId: bounds.weekId,
                        currentWeekLiveState: _state,
                        loading: _loadingWeek,
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
