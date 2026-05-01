import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../collect/collect_models.dart';
import '../collect/collect_parser.dart';
import '../collect/github_collect_repository.dart';
import '../config/github_token.dart';
import '../config/token_store.dart';
import '../diary/diary_models.dart';
import '../diary/github_diary_repository.dart';
import '../settings/settings_screen.dart';

/// Bottom tab index for [LifeOSApp] shell: 1 = 日记, 2 = 收藏.
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
      setState(() {
        _diaryToday = pair[0] as List<DiaryEntry>;
        _collectToday = pair[1] as List<CollectItem>;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (kIsWeb) {
      return _DecoratedShell(
        cs: cs,
        child: const _WebCorsHintBody(),
      );
    }

    if (_loadingToken) {
      return _DecoratedShell(
        cs: cs,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_diaryRepo.hasToken) {
      return _DecoratedShell(
        cs: cs,
        child: _TokenHintBody(cs: cs, onOpenSettings: _openSettings),
      );
    }

    final today = _today();
    final dateLine = DateFormat('y年M月d日 EEEE', 'zh_CN').format(today);

    return _DecoratedShell(
      cs: cs,
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
                                    style: GoogleFonts.newsreader(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dateLine,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _greeting(),
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: cs.onSurface,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
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
                        const SizedBox(height: 12),
                        _ConnectionChip(cs: cs),
                        if (_summaryError != null) ...[
                          const SizedBox(height: 12),
                          _ErrorBanner(message: _summaryError!, cs: cs),
                        ],
                        const SizedBox(height: 20),
                        _SectionTitle(cs: cs, icon: Icons.auto_stories_outlined, label: '今日日记'),
                        const SizedBox(height: 10),
                        _DiaryTodayCard(
                          cs: cs,
                          theme: theme,
                          entries: _diaryToday,
                          onOpenDiary: () => widget.onOpenTab(1),
                        ),
                        const SizedBox(height: 20),
                        _SectionTitle(cs: cs, icon: Icons.bookmark_outline, label: '今日收藏'),
                        const SizedBox(height: 10),
                        _CollectTodayCard(
                          cs: cs,
                          theme: theme,
                          items: _collectToday,
                          onOpenCollect: () => widget.onOpenTab(2),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          '快捷入口',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => widget.onOpenTab(1),
                                icon: const Icon(Icons.edit_note_outlined),
                                label: const Text('日记'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => widget.onOpenTab(2),
                                icon: const Icon(Icons.bookmark_border),
                                label: const Text('收藏'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: _openSettings,
                            icon: Icon(Icons.tune, size: 20, color: cs.primary),
                            label: Text('GitHub 与缓存设置', style: TextStyle(color: cs.primary)),
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
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
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
  const _DecoratedShell({
    required this.cs,
    required this.child,
  });

  final ColorScheme cs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.35),
            cs.surface,
          ],
        ),
      ),
      child: SafeArea(child: child),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.cloud_done_outlined, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          'GitHub 已连接',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.cs,
    required this.icon,
    required this.label,
  });

  final ColorScheme cs;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.newsreader(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.cs});

  final String message;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: cs.errorContainer.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onErrorContainer,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiaryTodayCard extends StatelessWidget {
  const _DiaryTodayCard({
    required this.cs,
    required this.theme,
    required this.entries,
    required this.onOpenDiary,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final List<DiaryEntry> entries;
  final VoidCallback onOpenDiary;

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
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDiary,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: entries.isEmpty
              ? Text(
                  '今天还没有日记条目。点按前往日历选择日期或新建记录。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
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
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_subtitle(entries[i]).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _subtitle(entries[i]),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
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
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.primary,
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
    required this.cs,
    required this.theme,
    required this.items,
    required this.onOpenCollect,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final List<CollectItem> items;
  final VoidCallback onOpenCollect;

  @override
  Widget build(BuildContext context) {
    final show = items.take(3).toList();
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenCollect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: items.isEmpty
              ? Text(
                  '今天还没有收藏。在仓库 collect/ 对应日期目录下添加条目后会显示在这里。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
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
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (show[i].preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          show[i].preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                    if (items.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '共 ${items.length} 条，点按查看全部',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.primary,
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

class _TokenHintBody extends StatelessWidget {
  const _TokenHintBody({required this.cs, required this.onOpenSettings});

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
                    '首页摘要、日记与收藏都从 GitHub 私有仓库 ForeverPx/my-ai-memory 读取。'
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

class _WebCorsHintBody extends StatelessWidget {
  const _WebCorsHintBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
                    '请在 iOS、Android 或桌面端运行本应用以同步私有仓库；'
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
