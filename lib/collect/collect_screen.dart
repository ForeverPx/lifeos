import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../config/github_repo_prefs.dart';
import '../config/github_token.dart';
import '../config/token_store.dart';
import '../settings/settings_screen.dart';
import 'collect_compose_screen.dart';
import 'collect_models.dart';
import 'collect_parser.dart';
import 'github_collect_repository.dart';

/// Matches each `[segment]` in a search string, including adjacent `[a][b]`.
final _bracketSearchToken = RegExp(r'\[([^\]]+)\]');

List<String> _bracketSearchTokensLower(String qLower) {
  return _bracketSearchToken
      .allMatches(qLower)
      .map((m) => m.group(1)!.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();
}

String _searchOutsideBracketsLower(String qLower) {
  return qLower
      .replaceAll(_bracketSearchToken, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

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

  Future<void> _openCompose() async {
    final n = DateTime.now();
    final day = DateTime(n.year, n.month, n.day);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CollectComposeScreen(
          repo: _repo,
          day: day,
        ),
      ),
    );
    if (changed == true && mounted) await _refresh();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    return Scaffold(
      backgroundColor: isDark ? colors.background : const Color(0xFFF5F7FA),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCompose,
        backgroundColor: const Color(0xFFF59E0B),
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
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
                                  fontWeight: FontWeight.w700,
                                  color: colors.foreground,
                                  height: 1.1,
                                  fontSize: 28,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() => _searchExpanded = !_searchExpanded);
                                if (!_searchExpanded) {
                                  _searchController.clear();
                                  _setQuery('');
                                }
                              },
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
                                  _searchExpanded ? Icons.close : Icons.search,
                                  size: 20,
                                  color: colors.mutedForeground,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
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
                        const SizedBox(height: 6),
                        Text(
                          hasQuery
                              ? '搜索结果：${resultCount ?? 0} 条（仅搜索已加载内容）'
                              : '下拉同步 · 按日期浏览 collect 目录',
                          style: typography.sm.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                        if (_loading) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '同步中…',
                                style: typography.sm.copyWith(
                                  color: colors.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState:
                        _searchExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    firstChild: const SizedBox(height: 0),
                    secondChild: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Container(
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
                                      const Icon(Icons.search),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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
                            repo: _repo,
                            onCollectChanged: _refresh,
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
        ],
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
    final tokens = _bracketSearchTokensLower(qLower);
    if (tokens.isEmpty) {
      return hay.contains(qLower);
    }
    for (final t in tokens) {
      if (!hay.contains(t)) return false;
    }
    final rest = _searchOutsideBracketsLower(qLower);
    if (rest.isNotEmpty && !hay.contains(rest)) return false;
    return true;
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.items,
    required this.loading,
    required this.showNotLoadedHint,
    required this.repo,
    required this.onCollectChanged,
  });

  final DateTime day;
  final List<CollectItem> items;
  final bool loading;
  final bool showNotLoadedHint;
  final GithubCollectRepository repo;
  final Future<void> Function() onCollectChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final label = DateFormat('yyyy年MM月dd日', 'zh_CN').format(day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.bookmark_rounded,
                size: 16,
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: typography.md.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.foreground,
              ),
            ),
            const Spacer(),
            if (loading)
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
          _CollectCard(
            item: item,
            repo: repo,
            onCollectChanged: onCollectChanged,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CollectCard extends StatelessWidget {
  const _CollectCard({
    required this.item,
    required this.repo,
    required this.onCollectChanged,
  });

  final CollectItem item;
  final GithubCollectRepository repo;
  final Future<void> Function() onCollectChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        showFSheet<void>(
          context: context,
          side: FLayout.btt,
          mainAxisMaxRatio: 0.88,
          builder: (ctx) => ColoredBox(
            color: FTheme.of(ctx).colors.background,
            child: _CollectDetailSheet(
              item: item,
              repo: repo,
              onCollectChanged: onCollectChanged,
            ),
          ),
        );
      },
      child: Container(
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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 72,
                  height: 72,
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                  child: Icon(
                    Icons.image_outlined,
                    size: 28,
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: typography.md.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.foreground,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.preview,
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                          height: 1.45,
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
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
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
                        const Spacer(),
                        Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: colors.mutedForeground,
                        ),
                      ],
                    ),
                  ],
                ),
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

class _CollectDetailSheet extends StatefulWidget {
  const _CollectDetailSheet({
    required this.item,
    required this.repo,
    required this.onCollectChanged,
  });

  final CollectItem item;
  final GithubCollectRepository repo;
  final Future<void> Function() onCollectChanged;

  @override
  State<_CollectDetailSheet> createState() => _CollectDetailSheetState();
}

class _CollectDetailSheetState extends State<_CollectDetailSheet> {
  bool _deleting = false;
  String? _deleteError;

  Future<void> _confirmDelete() async {
    final ok = await showFDialog<bool>(
      context: context,
      builder: (ctx, style, animation) => FDialog(
        title: const Text('删除这条收藏？'),
        body: Text(
          '将永久从 GitHub 仓库移除该文件：\n${widget.item.fileName}\n${widget.item.path}',
        ),
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
    if (ok != true || !mounted) return;

    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    try {
      await widget.repo.deleteCollectFile(path: widget.item.path);
      if (!mounted) return;
      showFToast(
        context: context,
        icon: const Icon(FIcons.trash2),
        title: const Text('已删除'),
      );
      Navigator.of(context).pop();
      await widget.onCollectChanged();
    } on GithubCollectException catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _deleteError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _deleteError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom;
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
                    widget.item.title,
                    style: typography.xl.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                      height: 1.2,
                    ),
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: _deleting ? null : () => Navigator.of(context).pop(),
                  child: const Icon(FIcons.x),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.item.path,
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: widget.item.body.trim().isEmpty
                    ? Text(
                        '（内容为空）',
                        style: typography.sm.copyWith(
                          height: 1.55,
                          color: colors.mutedForeground,
                        ),
                      )
                    : MarkdownBody(
                        data: widget.item.body,
                        styleSheet: _collectMarkdownSheet(theme, colors, typography),
                      ),
              ),
            ),
          ),
          if (_deleteError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FAlert(
                variant: FAlertVariant.destructive,
                title: Text(_deleteError!),
                icon: const Icon(FIcons.circleAlert),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
            child: FButton(
              variant: FButtonVariant.outline,
              onPress: _deleting ? null : _confirmDelete,
              prefix: _deleting
                  ? const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                  : const Icon(FIcons.trash2),
              child: Text(_deleting ? '删除中…' : '删除该文件'),
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
                    '收藏列表读取自 ${GitHubRepoPrefs.displayName} 仓库中的 collect 目录（按日期归档）。'
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
