import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = _query.trim().toLowerCase();

    if (kIsWeb) {
      return _WebCorsHint(cs: cs);
    }

    if (_loadingToken) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_repo.hasToken) {
      return _TokenHint(cs: cs, onOpenSettings: _openSettings);
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
            cs.surfaceContainerHighest.withValues(alpha: 0.35),
            cs.tertiaryContainer.withValues(alpha: 0.22),
            theme.scaffoldBackgroundColor,
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
                              style: GoogleFonts.newsreader(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() => _searchExpanded = !_searchExpanded);
                              if (!_searchExpanded) {
                                _searchController.clear();
                                _setQuery('');
                              }
                            },
                            tooltip: _searchExpanded ? '收起搜索' : '搜索',
                            icon: Icon(
                              _searchExpanded ? Icons.search_off_outlined : Icons.search_outlined,
                              color: cs.onSurfaceVariant,
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
                        'ForeverPx / my-ai-memory · collect',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loading)
                        Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '同步中…',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          hasQuery
                              ? '搜索结果：${resultCount ?? 0} 条（仅搜索已加载内容）'
                              : '下拉刷新 · 按日期展示收藏内容',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
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
                    child: Material(
                      color: cs.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchController,
                          builder: (context, value, _) {
                            final hasText = value.text.trim().isNotEmpty;
                            return TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onChanged: _onSearchChanged,
                              decoration: InputDecoration(
                                hintText: '搜索标题 / 正文 / 文件名',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: !hasText
                                    ? IconButton(
                                        tooltip: '收起',
                                        onPressed: () {
                                          setState(() => _searchExpanded = false);
                                          _searchController.clear();
                                          _setQuery('');
                                        },
                                        icon: const Icon(Icons.keyboard_arrow_up),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: '清空',
                                            onPressed: () {
                                              _searchController.clear();
                                              _setQuery('');
                                            },
                                            icon: const Icon(Icons.close),
                                          ),
                                          IconButton(
                                            tooltip: '收起',
                                            onPressed: () {
                                              setState(() => _searchExpanded = false);
                                              _searchController.clear();
                                              _setQuery('');
                                            },
                                            icon: const Icon(Icons.keyboard_arrow_up),
                                          ),
                                        ],
                                      ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            );
                          },
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
              if (filteredDays.isEmpty && !_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                    child: Text(
                      hasQuery ? '没有匹配的收藏内容。' : '还没有找到 collect/ 下的日期文件夹。',
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

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _setQuery(_searchController.text);
    });
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = DateFormat('yyyy年MM月dd日', 'zh_CN').format(day);

    return Material(
      elevation: 0,
      color: cs.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bookmark_border, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.newsreader(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (showNotLoadedHint)
              Text(
                '为保证速度，仅加载最近 30 天。下拉刷新会重新同步最近内容。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            if (showNotLoadedHint) const SizedBox(height: 10),
            if (!loading && items.isEmpty)
              Text(
                '这一天没有可展示的文本文件（仅识别 .md/.markdown/.txt）。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      elevation: 1.2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _CollectDetailSheet(item: item),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              if (item.preview.isNotEmpty)
                Text(
                  item.preview,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.fileName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.open_in_new, size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectDetailSheet extends StatelessWidget {
  const _CollectDetailSheet({required this.item});

  final CollectItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: GoogleFonts.newsreader(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.path,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SelectionArea(
                child: SingleChildScrollView(
                  child: item.body.trim().isEmpty
                      ? Text(
                          '（内容为空）',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : MarkdownBody(
                          data: item.body,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                            p: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.55,
                              color: cs.onSurfaceVariant,
                            ),
                            h1: GoogleFonts.newsreader(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                            h2: GoogleFonts.newsreader(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                            h3: GoogleFonts.newsreader(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                            code: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              color: cs.onSurface,
                            ),
                            codeblockPadding: const EdgeInsets.all(12),
                            codeblockDecoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.7),
                              ),
                            ),
                            blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            blockquoteDecoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border(
                                left: BorderSide(
                                  color: cs.primary.withValues(alpha: 0.65),
                                  width: 3,
                                ),
                              ),
                            ),
                            a: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
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
                    '请在 iOS、Android 或桌面端运行本应用以同步私有仓库收藏；'
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
                    '收藏从 GitHub 私有仓库 '
                    'ForeverPx/my-ai-memory 的 collect 目录读取。'
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

