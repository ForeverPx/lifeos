import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

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
  String? _busyLabel;
  final _picker = ImagePicker();
  final List<XFile> _images = [];

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

  Future<void> _pickImages() async {
    if (_busy) return;
    try {
      final maxToPick = 3 - _images.length;
      if (maxToPick <= 0) {
        showFToast(context: context, title: const Text('最多支持 3 张图片'));
        return;
      }

      final picked = await _picker.pickMultiImage(
        imageQuality: null, // keep original; we compress ourselves
      );
      if (picked.isEmpty) return;
      if (!mounted) return;

      final next = [..._images, ...picked];
      if (next.length > 3) {
        showFToast(context: context, title: const Text('最多支持 3 张图片，已自动截断'));
      }
      setState(() {
        _images
          ..clear()
          ..addAll(next.take(3));
      });
    } catch (e) {
      setState(() => _error = '选择图片失败：$e');
    }
  }

  Future<List<int>> _compressToJpegBytes(String path) async {
    final bytes = await FlutterImageCompress.compressWithFile(
      path,
      format: CompressFormat.jpeg,
      quality: 82,
      minWidth: 1600,
      minHeight: 1600,
    );
    if (bytes == null || bytes.isEmpty) {
      throw const GithubDiaryException('图片压缩失败（空输出）');
    }
    return bytes;
  }

  Widget _buildThumb(XFile img, {double extent = 86}) {
    return FutureBuilder<List<int>>(
      future: img.readAsBytes(),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            width: extent,
            height: extent,
            decoration: BoxDecoration(
              color: context.theme.colors.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const FCircularProgress(
              size: FCircularProgressSizeVariant.sm,
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            Uint8List.fromList(bytes),
            width: extent,
            height: extent,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

  String _buildMarkdownWithImages({
    required String body,
    required List<String> imageUrls,
  }) {
    final b = body.replaceAll('\r\n', '\n').trimRight();
    if (imageUrls.isEmpty) return b;
    final imgs = imageUrls
        .where((u) => u.trim().isNotEmpty)
        .map((u) => '![](${u.trim()})')
        .join('\n');
    if (b.trim().isEmpty) return imgs;
    return '$imgs\n\n$b';
  }

  Future<void> _submit() async {
    final text = _body.text.trim();
    if (text.isEmpty && _images.isEmpty) {
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
      _busyLabel = null;
      _error = null;
    });

    try {
      final ts = DateTime.now();
      final y = widget.year.toString();
      final m = widget.month.toString().padLeft(2, '0');
      final d = widget.day.toString().padLeft(2, '0');

      final uploadedUrls = <String>[];
      if (_images.isNotEmpty) {
        for (var i = 0; i < _images.length; i++) {
          final f = _images[i];
          if (!mounted) return;
          setState(() => _busyLabel = '压缩并上传图片 ${i + 1}/${_images.length}…');
          final bytes = await _compressToJpegBytes(f.path);
          final name = '${ts.millisecondsSinceEpoch}_${i + 1}.jpg';
          final snap = await widget.repo.uploadDiaryMediaBytes(
            fileName: name,
            bytes: bytes,
            message: 'lifeos: upload diary image $y-$m-$d',
            subdir: '$y/$m/$d',
          );
          uploadedUrls.add(snap.downloadUrl);
        }
      }

      if (!mounted) return;
      setState(() => _busyLabel = '调用大模型生成标题与标签…');
      final tagging = await LlmDiaryTagger.tagDiaryBody(
        _buildMarkdownWithImages(body: text, imageUrls: uploadedUrls),
      );

      final mergedBody = _buildMarkdownWithImages(
        body: _body.text.replaceAll('\r\n', '\n'),
        imageUrls: uploadedUrls,
      );
      final block = buildDiaryMarkdownBlock(
        timestamp: ts,
        tagging: tagging,
        body: mergedBody,
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
      _images.clear();
      setState(() {});
      if (!mounted) return;
      showFToast(context: context, title: const Text('已保存到 GitHub'));
      Navigator.of(context).pop(true);
    } on LlmDiaryTaggerException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyLabel = null;
        _error = e.message;
      });
    } on GithubDiaryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyLabel = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyLabel = null;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    // FScaffold already shrinks the body by viewInsets.bottom (resizeToAvoidBottomInset: true).
    // Only account for safe-area padding here to avoid double-counting.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final keyboardInset = MediaQuery.viewInsetsOf(
                        context,
                      ).bottom;
                      final thumbExtent = keyboardInset > 0 ? 56.0 : 86.0;
                      const chromeNoThumbs = 112.0;
                      final chromeThumbsExtra = _images.isEmpty
                          ? 0.0
                          : 8.0 + thumbExtent;
                      final fixedChrome = chromeNoThumbs + chromeThumbsExtra;
                      final fieldHeight = (constraints.maxHeight - fixedChrome)
                          .clamp(56.0, double.infinity);

                      return SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '图片（最多 3 张）',
                                    style: typography.sm.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colors.foreground,
                                    ),
                                  ),
                                ),
                                FButton.icon(
                                  variant: FButtonVariant.ghost,
                                  onPress: _busy ? null : _pickImages,
                                  child: const Icon(FIcons.imagePlus),
                                ),
                              ],
                            ),
                            if (_images.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: thumbExtent,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemBuilder: (context, index) {
                                    final img = _images[index];
                                    return Stack(
                                      children: [
                                        _buildThumb(img, extent: thumbExtent),
                                        Positioned(
                                          right: 4,
                                          top: 4,
                                          child: Material(
                                            color: Colors.black.withValues(
                                              alpha: 0.45,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              onTap: _busy
                                                  ? null
                                                  : () {
                                                      setState(
                                                        () => _images.removeAt(
                                                          index,
                                                        ),
                                                      );
                                                    },
                                              child: const Padding(
                                                padding: EdgeInsets.all(6),
                                                child: Icon(
                                                  Icons.close,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 10),
                                  itemCount: _images.length,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    '正文',
                                    style: typography.sm.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colors.foreground,
                                    ),
                                  ),
                                ),
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _body,
                                  builder: (context, value, _) {
                                    final n = value.text.characters.length;
                                    return Text(
                                      '$n 字',
                                      style: typography.xs.copyWith(
                                        color: colors.mutedForeground,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: fieldHeight,
                              child: FTextField(
                                control: FTextFieldControl.managed(
                                  controller: _body,
                                ),
                                focusNode: _bodyFocus,
                                autofocus: true,
                                label: null,
                                hint: '支持多段长文本…',
                                description: null,
                                maxLines: null,
                                expands: true,
                                keyboardType: TextInputType.multiline,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                enabled: !_busy,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
                child: FButton(
                  onPress: _busy ? null : _submit,
                  prefix: _busy
                      ? const FCircularProgress(
                          size: FCircularProgressSizeVariant.sm,
                        )
                      : const Icon(FIcons.sparkles),
                  child: Text(
                    _busy ? (_busyLabel ?? '打标签并保存中…') : '打标签并保存到 GitHub',
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
