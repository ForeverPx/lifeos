import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../config/llm_prefs_store.dart';
import 'github_collect_repository.dart';
import 'llm_collect_file_namer.dart';

/// Create a new file under GitHub `collect/<yyyy-MM-dd>/`.
class CollectComposeScreen extends StatefulWidget {
  const CollectComposeScreen({
    super.key,
    required this.repo,
    required this.day,
  });

  final GithubCollectRepository repo;
  final DateTime day;

  @override
  State<CollectComposeScreen> createState() => _CollectComposeScreenState();
}

class _CollectComposeScreenState extends State<CollectComposeScreen> {
  final _body = TextEditingController();
  final _bodyFocus = FocusNode(debugLabel: 'collect_compose_body');
  bool _busy = false;
  String? _error;

  static String _dayFolderLabel(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

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

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final fileName = await LlmCollectFileNamer.suggestMarkdownFileName(
        _body.text.replaceAll('\r\n', '\n'),
      );
      await widget.repo.createCollectMarkdownFile(
        day: widget.day,
        fileName: fileName,
        utf8Content: _body.text.replaceAll('\r\n', '\n'),
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
    } on LlmCollectFileNamerException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on GithubCollectException catch (e) {
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
    final folder = _dayFolderLabel(widget.day);

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
          title: const Text('新增收藏'),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '网页端无法直接写入 GitHub，请在移动端或桌面端新增收藏。',
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
          title: const Text('新增收藏'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'collect/$folder/ · 保存前将调用大模型根据正文生成文件名',
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: FButton(
                onPress: _busy ? null : _submit,
                prefix: _busy
                    ? const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                    : const Icon(FIcons.sparkles),
                child: Text(_busy ? '生成文件名并保存中…' : '生成文件名并保存到 GitHub'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
