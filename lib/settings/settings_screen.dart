import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../config/token_store.dart';
import '../collect/collect_cache.dart';
import '../diary/diary_cache.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onGitHubTokenChanged});

  final VoidCallback? onGitHubTokenChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _clearingCache = false;
  bool _clearingCollectCache = false;
  String? _savedHint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await TokenStore.readGitHubToken();
    if (!mounted) return;
    setState(() {
      _controller.text = token;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _savedHint = null;
    });
    try {
      await TokenStore.writeGitHubToken(_controller.text);
      widget.onGitHubTokenChanged?.call();
      if (mounted) {
        setState(() {
          _savedHint = '已保存';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _clearDiaryCache() async {
    final ok = await showFDialog<bool>(
      context: context,
      builder: (ctx, style, animation) => FDialog(
        title: const Text('清除日记缓存？'),
        body: const Text('将删除本地缓存的日记内容，不会影响 GitHub 上的数据。'),
        actions: [
          FButton(
            onPress: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _clearingCache = true);
    try {
      final removed = await DiaryCache.clearAll();
      if (!mounted) return;
      showFToast(
        context: context,
        title: Text('已清除 $removed 条日记缓存'),
      );
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _clearCollectCache() async {
    final ok = await showFDialog<bool>(
      context: context,
      builder: (ctx, style, animation) => FDialog(
        title: const Text('清除收藏缓存？'),
        body: const Text('将删除本地缓存的收藏内容，不会影响 GitHub 上的数据。'),
        actions: [
          FButton(
            onPress: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _clearingCollectCache = true);
    try {
      final removed = await CollectCache.clearAll();
      if (!mounted) return;
      showFToast(
        context: context,
        title: Text('已清除 $removed 条收藏缓存'),
      );
    } finally {
      if (mounted) setState(() => _clearingCollectCache = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;

    return FScaffold(
      header: FHeader.nested(
        prefixes: [
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: () => Navigator.of(context).pop(),
            child: const Icon(FIcons.chevronLeft),
          ),
        ],
        title: const Text('设置'),
      ),
      child: _loading
          ? const Center(child: FCircularProgress())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'GitHub',
                  style: typography.xl2.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                FCard.raw(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal Access Token',
                          style: typography.lg.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '用于读取私有仓库中的日记内容。建议使用 fine-grained token，并只授予需要访问的仓库权限。',
                          style: typography.sm.copyWith(
                            height: 1.45,
                            color: colors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FTextField.password(
                          control: FTextFieldControl.managed(controller: _controller),
                          label: const Text('GITHUB_TOKEN'),
                          hint: 'github_pat_...',
                          keyboardType: TextInputType.visiblePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                        if (kIsWeb) ...[
                          const SizedBox(height: 10),
                          Text(
                            '提示：Web 端会存到浏览器本地存储，且浏览器无法直接访问 GitHub API（跨域限制），日记同步建议在移动端/桌面端使用。',
                            style: typography.xs3.copyWith(
                              height: 1.4,
                              color: colors.mutedForeground,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            FButton(
                              onPress: _saving ? null : _save,
                              prefix: _saving
                                  ? const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                                  : const Icon(FIcons.save),
                              child: Text(_saving ? '保存中…' : '保存'),
                            ),
                            if (_savedHint != null) ...[
                              const SizedBox(width: 12),
                              Text(
                                _savedHint!,
                                style: typography.sm.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '存储',
                  style: typography.xl2.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                FTileGroup(
                  children: [
                    FTile(
                      prefix: Icon(FIcons.trash2, color: colors.mutedForeground),
                      title: const Text('清除日记缓存'),
                      subtitle: const Text('删除已缓存的历史日记内容'),
                      suffix: _clearingCache
                          ? const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                          : Icon(FIcons.chevronRight, color: colors.mutedForeground),
                      onPress: _clearingCache ? null : _clearDiaryCache,
                    ),
                    FTile(
                      prefix: Icon(FIcons.trash2, color: colors.mutedForeground),
                      title: const Text('清除收藏缓存'),
                      subtitle: const Text('删除已缓存的历史收藏内容'),
                      suffix: _clearingCollectCache
                          ? const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                          : Icon(FIcons.chevronRight, color: colors.mutedForeground),
                      onPress: _clearingCollectCache ? null : _clearCollectCache,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
