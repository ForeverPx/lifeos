import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../config/llm_prefs_store.dart';
import 'diary_markdown_builder.dart';
import 'github_diary_repository.dart';
import 'llm_diary_tagger.dart';

/// Write a long diary entry, tag via LLM, append to GitHub `daily_notes`.
class DiaryComposeScreen extends StatefulWidget {
  const DiaryComposeScreen({
    super.key,
    required this.repo,
    required this.year,
    required this.month,
    required this.day,
  });

  final GithubDiaryRepository repo;
  final int year;
  final int month;
  final int day;

  @override
  State<DiaryComposeScreen> createState() => _DiaryComposeScreenState();
}

class _DiaryComposeScreenState extends State<DiaryComposeScreen> {
  final _body = TextEditingController();
  final _bodyFocus = FocusNode(debugLabel: 'diary_compose_body');
  bool _busy = false;
  String? _error;

  void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  void initState() {
    super.initState();
    _body.addListener(_onBodyEdited);
  }

  void _onBodyEdited() {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  Future<void> _handleCloseAttempt() async {
    if (_busy) return;
    if (_body.text.trim().isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ok = await showFDialog<bool>(
      context: context,
      builder: (ctx, style, animation) => FDialog(
        title: const Text('放弃未保存的内容？'),
        body: const Text('当前正文尚未保存到 GitHub。'),
        actions: [
          FButton(
            onPress: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃'),
          ),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _body.removeListener(_onBodyEdited);
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _body.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请先输入正文');
      return;
    }
    if (!await LlmPrefsStore.isConfigured()) {
      setState(() => _error = '请先在设置中配置大模型 API 地址、Key 与模型');
      return;
    }

    _unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final tagging = await LlmDiaryTagger.tagDiaryBody(text);
      final block = buildDiaryMarkdownBlock(
        timestamp: DateTime.now(),
        tagging: tagging,
        body: _body.text.replaceAll('\r\n', '\n'),
      );
      await widget.repo.appendDiaryMarkdown(
        year: widget.year,
        month: widget.month,
        day: widget.day,
        markdownBlock: block,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _body.clear();
      setState(() {});
      if (!mounted) return;
      showFToast(
        context: context,
        title: const Text('已保存到 GitHub'),
      );
      Navigator.of(context).pop(true);
    } on LlmDiaryTaggerException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on GithubDiaryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final bottomInset =
        MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;

    if (kIsWeb) {
      return FScaffold(
        header: FHeader.nested(
          prefixes: [
            FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: () => Navigator.of(context).pop(),
              child: const Icon(FIcons.chevronLeft),
            ),
          ],
          title: const Text('新增日记'),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '网页端无法直接写入 GitHub，请在移动端或桌面端新增日记。',
              textAlign: TextAlign.center,
              style: typography.sm.copyWith(color: colors.mutedForeground),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _body.text.trim().isEmpty && !_busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleCloseAttempt();
      },
      child: FScaffold(
        header: FHeader.nested(
          prefixes: [
            FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: _busy ? null : () => _handleCloseAttempt(),
              child: const Icon(FIcons.chevronLeft),
            ),
          ],
          title: const Text('新增日记'),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _unfocus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  '${widget.year}-${widget.month.toString().padLeft(2, '0')}-${widget.day.toString().padLeft(2, '0')} · 保存前将调用大模型生成标题与标签',
                  style: typography.xs.copyWith(color: colors.mutedForeground),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: FAlert(
                    variant: FAlertVariant.destructive,
                    title: Text(_error!),
                    icon: const Icon(FIcons.circleAlert),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: FTextField(
                    control: FTextFieldControl.managed(controller: _body),
                    focusNode: _bodyFocus,
                    autofocus: true,
                    label: const Text('正文'),
                    hint: '支持多段长文本…',
                    description: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _body,
                      builder: (context, value, _) {
                        final n = value.text.characters.length;
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$n 字',
                            style: typography.xs.copyWith(color: colors.mutedForeground),
                          ),
                        );
                      },
                    ),
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    enabled: !_busy,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
                child: FButton(
                  onPress: _busy ? null : _submit,
                  prefix: _busy
                      ? const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                      : const Icon(FIcons.sparkles),
                  child: Text(_busy ? '打标签并保存中…' : '打标签并保存到 GitHub'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
