import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/token_store.dart';
import '../diary/diary_cache.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onGitHubTokenChanged});

  final VoidCallback? onGitHubTokenChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;
  bool _clearingCache = false;
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除日记缓存？'),
        content: const Text('将删除本地缓存的日记内容，不会影响 GitHub 上的数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _clearingCache = true);
    try {
      final removed = await DiaryCache.clearAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清除 $removed 条日记缓存')),
      );
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'GitHub',
                  style: GoogleFonts.newsreader(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: cs.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal Access Token',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '用于读取私有仓库中的日记内容。建议使用 fine-grained token，并只授予需要访问的仓库权限。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _controller,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          decoration: InputDecoration(
                            labelText: 'GITHUB_TOKEN',
                            hintText: 'github_pat_...',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? '显示' : '隐藏',
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (kIsWeb) ...[
                          const SizedBox(height: 10),
                          Text(
                            '提示：Web 端会存到浏览器本地存储，且浏览器无法直接访问 GitHub API（跨域限制），日记同步建议在移动端/桌面端使用。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(_saving ? '保存中…' : '保存'),
                            ),
                            if (_savedHint != null) ...[
                              const SizedBox(width: 12),
                              Text(
                                _savedHint!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.tertiary,
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
                  style: GoogleFonts.newsreader(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: cs.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: cs.onSurfaceVariant,
                        ),
                        title: const Text('清除日记缓存'),
                        subtitle: const Text('删除已缓存的历史日记内容'),
                        trailing: _clearingCache
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: _clearingCache ? null : _clearDiaryCache,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

