import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../config/github_token.dart';
import '../config/token_store.dart';
import '../settings/settings_screen.dart';
import 'collect_models.dart';
import 'collect_parser.dart';
import 'github_collect_repository.dart';

class CollectScreen extends StatefulWidget {
  const CollectScreen({super.key});

  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  final _repo = GithubCollectRepository();
  bool _loadingToken = true;

  bool _loading = false;
  String? _error;

  final List<DateTime> _days = [];
  final Map<DateTime, List<CollectItem>> _itemsByDay = {};

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  bool _searchExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTokenAndRefresh();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTokenAndRefresh() async {
    final stored = await TokenStore.readGitHubToken();
    final token = stored.trim().isNotEmpty ? stored : GitHubToken.value;
    if (!mounted) return;
    setState(() {
      _loadingToken = false;
      _repo.setToken(token);
    });
    await _refresh();
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

  Future<void> _refresh() async {
    if (!_repo.hasToken) return;
    setState(() {
      _loading = true;
      _error = null;
      _days.clear();
      _itemsByDay.clear();
    });

    try {
      final days = await _repo.listDays(limit: 60);
      if (!mounted) return;
      setState(() {
        _days.addAll(days);
      });

      // Load newest few days first, then continue.
      final loadDays = days.take(30).toList();
      for (final day in loadDays) {
        final files = await _repo.listFilesForDay(day);
        final items = <CollectItem>[];
        for (final f in files) {
          final text = await _repo.fetchFileContent(
            path: f.path,
            sha: f.sha,
            allowCache: day.isBefore(_today()),
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
              preview: previewFromBody(body),
            ),
          );
        }
        if (!mounted) return;
        setState(() {
          _itemsByDay[day] = items;
        });
      }
    } on GithubCollectException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final q = _query.trim().toLowerCase();

    if (kIsWeb) {
      return const _WebCorsHint();
    }

    if (_loadingToken) {
      return const Center(child: FCircularProgress());
    }

    if (!_repo.hasToken) {
      return _TokenHint(onOpenSettings: _openSettings);
    }

    final hasQuery = q.isNotEmpty;
    final loadedDayKeys = _itemsByDay.keys.toSet();
    final filteredDays = hasQuery
        ? _days.where((d) {
            if (!loadedDayKeys.contains(d)) return false;
            final items = _itemsByDay[d] ?? const <CollectItem>[];
            return items.any((it) => _matchesQuery(it, q));
          }).toList()
        : _days;

    final resultCount = hasQuery
        ? filteredDays.fold<int>(
            0,
            (sum, d) =>
                sum +
                (_itemsByDay[d] ?? const <CollectItem>[])
                    .where((it) => _matchesQuery(it, q))
                    .length,
          )
        : null;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.secondary.withValues(alpha: 0.4),
            colors.primary.withValues(alpha: 0.06),
            colors.background,
          ],
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
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
                              '收藏',
                              style: typography.xl2.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.foreground,
                                height: 1.1,
                              ),
                            ),
                          ),
                          FButton.icon(
                            variant: FButtonVariant.ghost,
                            onPress: () {
                              setState(() => _searchExpanded = !_searchExpanded);
                              if (!_searchExpanded) {
                                _searchController.clear();
                                _setQuery('');
                              }
                            },
                            child: Icon(
                              _searchExpanded ? FIcons.searchX : FIcons.search,
                              color: colors.mutedForeground,
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
                        'ForeverPx / my-ai-memory · collect',
                        style: typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loading)
                        Row(
                          children: [
                            const FCircularProgress(
                              size: FCircularProgressSizeVariant.sm,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '同步中…',
                              style: typography.sm.copyWith(
                                color: colors.mutedForeground,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          hasQuery
                              ? '搜索结果：${resultCount ?? 0} 条（仅搜索已加载内容）'
                              : '下拉刷新 · 按日期展示收藏内容',
                          style: typography.sm.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState:
                      _searchExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: const SizedBox(height: 0),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: FCard.raw(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FTextField(
                              control: FTextFieldControl.managed(
                                controller: _searchController,
                                onChange: (_) {
                                  _searchDebounce?.cancel();
                                  _searchDebounce = Timer(
                                    const Duration(milliseconds: 180),
                                    () {
                                      if (!mounted) return;
                                      _setQuery(_searchController.text);
                                    },
                                  );
                                },
                              ),
                              hint: '搜索标题 / 正文 / 文件名',
                              textInputAction: TextInputAction.search,
                              prefixBuilder: (c, style, variants) =>
                                  FTextField.prefixIconBuilder(
                                    c,
                                    style,
                                    variants,
                                    const Icon(FIcons.search),
                                  ),
                              clearable: (v) => v.text.trim().isNotEmpty,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FButton(
                                variant: FButtonVariant.ghost,
                                onPress: () {
                                  setState(() => _searchExpanded = false);
                                  _searchController.clear();
                                  _setQuery('');
                                },
                                child: const Text('收起'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
              if (filteredDays.isEmpty && !_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                    child: Text(
                      hasQuery ? '没有匹配的收藏内容。' : '还没有找到 collect/ 下的日期文件夹。',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final day = filteredDays[index];
                      final items = hasQuery
                          ? (_itemsByDay[day] ?? const <CollectItem>[])
                              .where((it) => _matchesQuery(it, q))
                              .toList()
                          : (_itemsByDay[day] ?? const <CollectItem>[]);
                      final isLoaded = _itemsByDay.containsKey(day);
                      final originalIndex = _days.indexOf(day);
                      final isPlannedToLoad = originalIndex != -1 && originalIndex < 30;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _DaySection(
                          day: day,
                          items: items,
                          loading: _loading && isPlannedToLoad && !isLoaded,
                          showNotLoadedHint: !isPlannedToLoad && !isLoaded,
                        ),
                      );
                    },
                    childCount: filteredDays.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setQuery(String v) {
    final next = v.trim();
    if (next == _query) return;
    setState(() => _query = next);
  }

  bool _matchesQuery(CollectItem item, String qLower) {
    if (qLower.isEmpty) return true;
    final hay = '${item.title}\n${item.fileName}\n${item.body}'.toLowerCase();
    return hay.contains(qLower);
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.items,
    required this.loading,
    required this.showNotLoadedHint,
  });

  final DateTime day;
  final List<CollectItem> items;
  final bool loading;
  final bool showNotLoadedHint;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final label = DateFormat('yyyy年MM月dd日', 'zh_CN').format(day);

    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(FIcons.bookmark, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: typography.xl.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                    height: 1.2,
                  ),
                ),
                const Spacer(),
                if (loading)
                  const FCircularProgress(
                    size: FCircularProgressSizeVariant.sm,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (showNotLoadedHint)
              Text(
                '为保证速度，仅加载最近 30 天。下拉刷新会重新同步最近内容。',
                style: typography.xs.copyWith(
                  color: colors.mutedForeground,
                  height: 1.35,
                ),
              ),
            if (showNotLoadedHint) const SizedBox(height: 10),
            if (!loading && items.isEmpty)
              Text(
                '这一天没有可展示的文本文件（仅识别 .md/.markdown/.txt）。',
                style: typography.sm.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            for (final item in items) ...[
              _CollectCard(item: item),
              const SizedBox(height: 12),
            ],
            if (items.isNotEmpty) const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

class _CollectCard extends StatelessWidget {
  const _CollectCard({required this.item});

  final CollectItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return FCard.raw(
      child: FTappable.static(
        onPress: () {
          showFSheet<void>(
            context: context,
            side: FLayout.btt,
            mainAxisMaxRatio: 0.88,
            builder: (ctx) => ColoredBox(
              color: FTheme.of(ctx).colors.background,
              child: _CollectDetailSheet(item: item),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: typography.lg.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.foreground,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              if (item.preview.isNotEmpty)
                Text(
                  item.preview,
                  style: typography.sm.copyWith(
                    color: colors.mutedForeground,
                    height: 1.45,
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(FIcons.fileText, size: 16, color: colors.mutedForeground),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.fileName,
                      style: typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(FIcons.externalLink, size: 16, color: colors.mutedForeground),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

MarkdownStyleSheet _collectMarkdownSheet(ThemeData theme, FColors colors, FTypography typography) {
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: typography.sm.copyWith(height: 1.55, color: colors.mutedForeground),
    h1: typography.xl2.copyWith(fontWeight: FontWeight.w700, color: colors.foreground, height: 1.2),
    h2: typography.xl.copyWith(fontWeight: FontWeight.w700, color: colors.foreground, height: 1.2),
    h3: typography.lg.copyWith(fontWeight: FontWeight.w700, color: colors.foreground, height: 1.2),
    code: typography.sm.copyWith(fontFamily: 'monospace', color: colors.foreground),
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
        left: BorderSide(color: colors.primary.withValues(alpha: 0.85), width: 3),
      ),
    ),
    a: typography.sm.copyWith(color: colors.primary, decoration: TextDecoration.underline),
  );
}

class _CollectDetailSheet extends StatelessWidget {
  const _CollectDetailSheet({required this.item});

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
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
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
                        styleSheet: _collectMarkdownSheet(theme, colors, typography),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
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
                    '浏览器无法直接访问 GitHub REST API（跨域策略）。'
                    '请在 iOS、Android 或桌面端运行本应用以同步私有仓库收藏；'
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
                    '收藏从 GitHub 私有仓库 '
                    'ForeverPx/my-ai-memory 的 collect 目录读取。'
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

