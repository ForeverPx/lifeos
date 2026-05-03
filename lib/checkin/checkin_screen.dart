import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/github_token.dart';
import '../config/token_store.dart';
import '../settings/settings_screen.dart';
import 'checkin_models.dart';
import 'checkin_week.dart';
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
      final snap = await _repo.fetchWeek(bounds.weekId);
      if (!mounted) return;
      setState(() {
        _state = snap.state;
        _fileSha = snap.fileSha;
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
      final newSha = await _repo.saveWeek(
        weekId: bounds.weekId,
        state: next,
        previousSha: previousSha,
      );
      if (!mounted) return;
      setState(() {
        _fileSha = newSha;
        _saving = false;
      });
    } on GithubCheckinException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = previousState;
        _fileSha = previousSha;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打卡同步失败：${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = previousState;
        _fileSha = previousSha;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打卡同步失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (kIsWeb) {
      return _WebHint(cs: cs);
    }

    if (_loadingToken) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_repo.hasToken) {
      return _TokenHint(cs: cs, onOpenSettings: _openSettings);
    }

    final today = _today();
    final bounds = CheckinWeekBounds.forLocalDate(today);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHighest.withValues(alpha: 0.35),
            cs.primaryContainer.withValues(alpha: 0.2),
            theme.scaffoldBackgroundColor,
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
                        'ForeverPx / my-ai-memory · checkins（按周）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '仅展示与编辑本周（周一至周日）的打卡记录。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      if (_loadError != null) ...[
                        const SizedBox(height: 14),
                        Material(
                          color: cs.errorContainer.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline, color: cs.error, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _loadError!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onErrorContainer,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
  const _WebHint({required this.cs});

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
                    '请在 iOS、Android 或桌面端运行本应用以同步打卡数据。',
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
                    '打卡数据写入 GitHub 私有仓库 '
                    'ForeverPx/my-ai-memory 的 checkins 目录（按周）。'
                    '请使用带 repo 权限的 Personal Access Token，并在设置中填写。',
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
