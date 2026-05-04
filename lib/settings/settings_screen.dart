import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../config/github_repo_prefs.dart';
import '../config/llm_prefs_store.dart';
import '../config/theme_prefs.dart';
import '../config/token_store.dart';
import '../collect/collect_cache.dart';
import '../diary/diary_cache.dart';
import '../diary/llm_diary_tagger.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onGitHubTokenChanged});

  final VoidCallback? onGitHubTokenChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  final _githubOwnerController = TextEditingController();
  final _githubRepoController = TextEditingController();
  final _llmUrlController = TextEditingController();
  final _llmModelController = TextEditingController();
  final _llmKeyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _savingLlm = false;
  bool _testingLlm = false;
  bool _clearingCache = false;
  bool _clearingCollectCache = false;
  String? _savedHint;
  String? _savedLlmHint;
  LlmProviderKind _llmProvider = LlmProviderKind.openAiCompatible;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await TokenStore.readGitHubToken();
    final githubOwner = await GitHubRepoPrefs.readOwnerForEdit();
    final githubRepo = await GitHubRepoPrefs.readRepoForEdit();
    final provider = await LlmPrefsStore.readProvider();
    final llmUrl = await LlmPrefsStore.readBaseUrl();
    final llmModel = await LlmPrefsStore.readModel();
    final llmKey = await LlmPrefsStore.readApiKey();
    if (!mounted) return;
    setState(() {
      _controller.text = token;
      _githubOwnerController.text = githubOwner;
      _githubRepoController.text = githubRepo;
      _llmProvider = provider;
      _llmUrlController.text = llmUrl;
      _llmModelController.text = llmModel;
      _llmKeyController.text = llmKey;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _githubOwnerController.dispose();
    _githubRepoController.dispose();
    _llmUrlController.dispose();
    _llmModelController.dispose();
    _llmKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _savedHint = null;
    });
    try {
      await TokenStore.writeGitHubToken(_controller.text);
      await GitHubRepoPrefs.writeFromUserInput(
        _githubOwnerController.text,
        _githubRepoController.text,
      );
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

  Future<void> _saveLlm() async {
    setState(() {
      _savingLlm = true;
      _savedLlmHint = null;
    });
    try {
      await LlmPrefsStore.writeProvider(_llmProvider);
      await LlmPrefsStore.writeBaseUrl(_llmUrlController.text);
      await LlmPrefsStore.writeModel(_llmModelController.text);
      await LlmPrefsStore.writeApiKey(_llmKeyController.text);
      if (mounted) {
        setState(() {
          _savedLlmHint = '已保存';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _savingLlm = false);
      }
    }
  }

  Future<void> _testLlmConnection() async {
    if (_testingLlm || _savingLlm) return;
    setState(() => _testingLlm = true);
    try {
      final msg = await LlmDiaryTagger.verifyConnection(
        provider: _llmProvider,
        baseUrl: _llmUrlController.text,
        apiKey: _llmKeyController.text,
        model: _llmModelController.text,
      );
      if (!mounted) return;
      showFToast(
        context: context,
        icon: const Icon(FIcons.cloudCheck),
        title: Text(msg),
        duration: const Duration(seconds: 6),
      );
    } on LlmDiaryTaggerException catch (e) {
      if (!mounted) return;
      final body = e.body;
      final typo = context.theme.typography;
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        icon: const Icon(FIcons.circleAlert),
        title: Text(e.message),
        description: body != null && body.trim().isNotEmpty
            ? Text(
                body.length > 320 ? '${body.substring(0, 320)}…' : body,
                style: typo.xs3.copyWith(height: 1.35),
              )
            : null,
        duration: const Duration(seconds: 8),
      );
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        icon: const Icon(FIcons.circleAlert),
        title: Text('请求异常：$e'),
        duration: const Duration(seconds: 6),
      );
    } finally {
      if (mounted) setState(() => _testingLlm = false);
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
                  '外观',
                  style: typography.xl2.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                FTileGroup(
                  children: [
                    FTile(
                      prefix: Icon(FIcons.sunMoon, color: colors.mutedForeground),
                      title: const Text('跟随系统'),
                      subtitle: const Text('根据系统浅色 / 深色自动切换'),
                      suffix: ThemePrefs.notifier.value == AppThemeMode.system
                          ? Icon(FIcons.check, color: colors.primary)
                          : Icon(FIcons.chevronRight, color: colors.mutedForeground),
                      onPress: () => ThemePrefs.set(AppThemeMode.system),
                    ),
                    FTile(
                      prefix: Icon(FIcons.sun, color: colors.mutedForeground),
                      title: const Text('亮色'),
                      subtitle: const Text('始终使用浅色界面'),
                      suffix: ThemePrefs.notifier.value == AppThemeMode.light
                          ? Icon(FIcons.check, color: colors.primary)
                          : Icon(FIcons.chevronRight, color: colors.mutedForeground),
                      onPress: () => ThemePrefs.set(AppThemeMode.light),
                    ),
                    FTile(
                      prefix: Icon(FIcons.moon, color: colors.mutedForeground),
                      title: const Text('暗色'),
                      subtitle: const Text('始终使用深色界面'),
                      suffix: ThemePrefs.notifier.value == AppThemeMode.dark
                          ? Icon(FIcons.check, color: colors.primary)
                          : Icon(FIcons.chevronRight, color: colors.mutedForeground),
                      onPress: () => ThemePrefs.set(AppThemeMode.dark),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
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
                          '数据仓库',
                          style: typography.lg.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '日记、收藏、打卡等数据读写的 GitHub 仓库（默认 '
                          '${GitHubRepoPrefs.defaultOwner}/${GitHubRepoPrefs.defaultRepo}）。'
                          '修改后请一并保存；PAT 需对该仓库有 Contents 与 Metadata 读/写权限。',
                          style: typography.sm.copyWith(
                            height: 1.45,
                            color: colors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FTextField(
                          control: FTextFieldControl.managed(
                            controller: _githubOwnerController,
                          ),
                          label: const Text('仓库所有者（用户名或组织）'),
                          hint: GitHubRepoPrefs.defaultOwner,
                          keyboardType: TextInputType.text,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                        const SizedBox(height: 14),
                        FTextField(
                          control: FTextFieldControl.managed(
                            controller: _githubRepoController,
                          ),
                          label: const Text('仓库名'),
                          hint: GitHubRepoPrefs.defaultRepo,
                          keyboardType: TextInputType.text,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Personal Access Token',
                          style: typography.lg.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '用于访问上述私有库。'
                          '建议使用 fine-grained PAT，仅授予该仓库的 Contents 与 Metadata 读/写所需权限。',
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
                            '提示：Token 会保存在本机浏览器存储。受 CORS 限制，网页端无法直接调用 GitHub API，同步请在 iOS / Android / 桌面端完成。',
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
                  '大模型（日记打标签）',
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
                          'API 形态',
                          style: typography.lg.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        FTileGroup(
                          children: [
                            FTile(
                              title: const Text('OpenAI 兼容'),
                              subtitle: const Text('POST …/v1/chat/completions'),
                              suffix: _llmProvider == LlmProviderKind.openAiCompatible
                                  ? Icon(FIcons.check, color: colors.primary)
                                  : Icon(FIcons.chevronRight, color: colors.mutedForeground),
                              onPress: () => setState(
                                () => _llmProvider = LlmProviderKind.openAiCompatible,
                              ),
                            ),
                            FTile(
                              title: const Text('Anthropic'),
                              subtitle: const Text('POST …/v1/messages'),
                              suffix: _llmProvider == LlmProviderKind.anthropic
                                  ? Icon(FIcons.check, color: colors.primary)
                                  : Icon(FIcons.chevronRight, color: colors.mutedForeground),
                              onPress: () =>
                                  setState(() => _llmProvider = LlmProviderKind.anthropic),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'API 根地址',
                          style: typography.lg.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'OpenAI 兼容示例：https://api.openai.com/v1 或自建网关根路径。'
                          'Anthropic 示例：https://api.anthropic.com',
                          style: typography.sm.copyWith(
                            height: 1.45,
                            color: colors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FTextField(
                          control: FTextFieldControl.managed(controller: _llmUrlController),
                          label: const Text('Base URL'),
                          hint: 'https://…',
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                        const SizedBox(height: 14),
                        FTextField(
                          control: FTextFieldControl.managed(controller: _llmModelController),
                          label: const Text('模型 ID'),
                          hint: 'gpt-4o-mini / claude-sonnet-4-20250514',
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                        const SizedBox(height: 14),
                        FTextField.password(
                          control: FTextFieldControl.managed(controller: _llmKeyController),
                          label: const Text('API Key'),
                          hint: 'sk-… 或 Anthropic secret key',
                          keyboardType: TextInputType.visiblePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FButton(
                              variant: FButtonVariant.outline,
                              onPress: (_testingLlm || _savingLlm) ? null : _testLlmConnection,
                              prefix: _testingLlm
                                  ? const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                                  : const Icon(FIcons.cloudCheck),
                              child: Text(_testingLlm ? '测试中…' : '测试连接'),
                            ),
                            FButton(
                              onPress: (_savingLlm || _testingLlm) ? null : _saveLlm,
                              prefix: _savingLlm
                                  ? const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                                  : const Icon(FIcons.save),
                              child: Text(_savingLlm ? '保存中…' : '保存大模型配置'),
                            ),
                            if (_savedLlmHint != null)
                              Text(
                                _savedLlmHint!,
                                style: typography.sm.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '「测试连接」使用上方输入框中的配置，无需先点保存。',
                          style: typography.xs3.copyWith(
                            height: 1.4,
                            color: colors.mutedForeground,
                          ),
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
