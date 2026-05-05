import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/llm_prefs_store.dart';
import '../config/openai_message_content.dart';

class LlmCollectFileNamerException implements Exception {
  const LlmCollectFileNamerException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => message;
}

abstract final class LlmCollectFileNamer {
  LlmCollectFileNamer._();

  static const _systemPrompt =
      '你是中文助手。用户会提供一段打算存入知识库收藏的 Markdown 正文。请根据内容总结出一个适合作为磁盘文件名的短语。'
      '输出且仅输出一个 JSON 对象（不要 markdown 代码围栏），格式为：{"fileName":"名称.md"}。'
      'fileName 要求：必须以 .md 结尾；只使用中文、英文、数字、连字符 - 与下划线 _；不要空格、不要路径符号、不要引号、不要换行；'
      '能概括正文主题；含后缀总长度不超过 72 个字符。';

  static Uri _openAiChatUri(String rawBase) {
    var s = rawBase.trim();
    if (s.isEmpty) {
      throw const LlmCollectFileNamerException('未配置 API 地址');
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final u = Uri.parse(s);
    if (u.path.contains('chat/completions')) {
      return u;
    }
    var p = u.path;
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    if (p.isEmpty || p == '/') {
      return u.replace(path: '/v1/chat/completions');
    }
    if (p.endsWith('/v1')) {
      return u.replace(path: '$p/chat/completions');
    }
    return u.replace(path: '$p/chat/completions');
  }

  static Uri _anthropicMessagesUri(String rawBase) {
    var s = rawBase.trim();
    if (s.isEmpty) {
      throw const LlmCollectFileNamerException('未配置 API 地址');
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final u = Uri.parse(s);
    if (u.path.contains('/v1/messages')) {
      return u;
    }
    var p = u.path;
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    if (p.isEmpty || p == '/') {
      return u.replace(path: '/v1/messages');
    }
    if (p.endsWith('/v1')) {
      return u.replace(path: '$p/messages');
    }
    return u.replace(path: '$p/v1/messages');
  }

  static String _stripJsonFences(String raw) {
    var t = raw.trim();
    if (t.startsWith('```')) {
      final firstNl = t.indexOf('\n');
      if (firstNl != -1) {
        t = t.substring(firstNl + 1);
      } else {
        t = t.substring(3);
      }
      t = t.trim();
      if (t.endsWith('```')) {
        t = t.substring(0, t.length - 3).trim();
      }
    }
    return t;
  }

  /// Normalizes model output into a single safe `.md` basename.
  static String finalizeMarkdownFileName(String rawFromModel) {
    var s = rawFromModel.trim();
    if (s.isEmpty) {
      throw const LlmCollectFileNamerException('模型返回的文件名为空');
    }
    s = s.replaceAll(RegExp(r'[/\\:*?"<>|\s]'), '-');
    s = s.replaceAll(RegExp(r'-+'), '-');
    s = s.trim();
    if (s.isEmpty) {
      throw const LlmCollectFileNamerException('文件名清理后为空');
    }
    final lower = s.toLowerCase();
    if (!lower.endsWith('.md')) {
      if (lower.endsWith('.markdown') || lower.endsWith('.txt')) {
        // keep as-is if model used allowed suffix
      } else {
        s = '$s.md';
      }
    }
    if (s.length > 72) {
      final dot = s.lastIndexOf('.');
      if (dot <= 0) {
        s = s.substring(0, 72);
      } else {
        final ext = s.substring(dot);
        final stem = s.substring(0, dot);
        if (ext.length >= 72) {
          s = s.substring(0, 72);
        } else {
          final maxStem = 72 - ext.length;
          final cut = stem.length > maxStem ? stem.substring(0, maxStem) : stem;
          s = '$cut$ext';
        }
      }
    }
    if (s.startsWith('.') || s.contains('..')) {
      throw const LlmCollectFileNamerException('文件名不合法');
    }
    return s;
  }

  static String _parseFileNameJson(String raw) {
    final t = _stripJsonFences(raw);
    final decoded = jsonDecode(t);
    if (decoded is! Map<String, dynamic>) {
      throw const LlmCollectFileNamerException('模型返回不是 JSON 对象');
    }
    final name = (decoded['fileName'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      throw const LlmCollectFileNamerException('模型未返回 fileName');
    }
    return finalizeMarkdownFileName(name);
  }

  /// Returns a basename like `读书笔记-foo.md` from [body] (trimmed markdown/text).
  static Future<String> suggestMarkdownFileName(String body) async {
    final provider = await LlmPrefsStore.readProvider();
    final baseUrl = (await LlmPrefsStore.readBaseUrl()).trim();
    final apiKey = (await LlmPrefsStore.readApiKey()).trim();
    final model = (await LlmPrefsStore.readModel()).trim();
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      throw const LlmCollectFileNamerException(
        '请先在设置中填写大模型 API 地址、API Key 与模型名称',
      );
    }

    final userContent = '收藏正文如下：\n\n$body';

    switch (provider) {
      case LlmProviderKind.openAiCompatible:
        return _nameOpenAiCompatible(
          uri: _openAiChatUri(baseUrl),
          apiKey: apiKey,
          model: model,
          userContent: userContent,
        );
      case LlmProviderKind.anthropic:
        return _nameAnthropic(
          uri: _anthropicMessagesUri(baseUrl),
          apiKey: apiKey,
          model: model,
          userContent: userContent,
        );
    }
  }

  static Future<String> _nameOpenAiCompatible({
    required Uri uri,
    required String apiKey,
    required String model,
    required String userContent,
  }) async {
    final payload = jsonEncode({
      'model': model,
      'temperature': 0.3,
      'max_tokens': 4096,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userContent},
      ],
    });
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: payload,
    );
    if (res.statusCode != 200) {
      throw LlmCollectFileNamerException(
        'OpenAI 兼容接口错误 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final map = unwrapOpenAiChatResponseMap(jsonDecode(res.body) as Map<String, dynamic>);
    final choices = map['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmCollectFileNamerException('响应中无 choices');
    }
    final text = openAiAssistantTextFromChoice(choices.first);
    if (text == null || text.isEmpty) {
      final hint = openAiToolCallsBlockingHint(choices.first);
      throw LlmCollectFileNamerException(
        hint ?? '模型未返回文本内容：${briefOpenAiResponseForError(res.body)}',
        body: res.body,
      );
    }
    return _parseFileNameJson(text);
  }

  static Future<String> _nameAnthropic({
    required Uri uri,
    required String apiKey,
    required String model,
    required String userContent,
  }) async {
    final payload = jsonEncode({
      'model': model,
      'max_tokens': 256,
      'system': _systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': userContent,
        },
      ],
    });
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: payload,
    );
    if (res.statusCode != 200) {
      throw LlmCollectFileNamerException(
        'Anthropic 接口错误 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final content = map['content'];
    if (content is! List || content.isEmpty) {
      throw const LlmCollectFileNamerException('响应中无 content');
    }
    final block = content.first;
    if (block is! Map<String, dynamic>) {
      throw const LlmCollectFileNamerException('content 块格式异常');
    }
    final text = block['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const LlmCollectFileNamerException('模型未返回文本');
    }
    return _parseFileNameJson(text);
  }
}
