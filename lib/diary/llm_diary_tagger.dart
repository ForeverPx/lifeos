import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/llm_prefs_store.dart';

/// Result of LLM tagging for a diary entry.
class DiaryTaggingResult {
  const DiaryTaggingResult({
    required this.title,
    required this.tags,
  });

  final String title;
  final List<String> tags;
}

class LlmDiaryTaggerException implements Exception {
  const LlmDiaryTaggerException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => message;
}

abstract final class LlmDiaryTagger {
  LlmDiaryTagger._();

  static const _systemPrompt =
      '你是中文日记助手。用户会提供一段日记正文。请输出且仅输出一个 JSON 对象（不要 markdown 代码围栏），'
      '格式为：{"title":"10字以内的简短标题","tags":["#主题1","#主题2"]}。'
      'tags 为 3 到 8 个中文或英文标签，每个以 # 开头，不要空格，不要换行，不要重复。'
      'title 中不要出现竖线 | 或换行。';

  static Uri _openAiChatUri(String rawBase) {
    var s = rawBase.trim();
    if (s.isEmpty) {
      throw const LlmDiaryTaggerException('未配置 API 地址');
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
      throw const LlmDiaryTaggerException('未配置 API 地址');
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

  static String _briefApiError(String body) {
    try {
      final o = jsonDecode(body);
      if (o is Map<String, dynamic>) {
        final err = o['error'];
        if (err is Map<String, dynamic>) {
          final m = err['message'] as String?;
          if (m != null && m.trim().isNotEmpty) return m.trim();
        }
        final msg = o['message'] as String?;
        if (msg != null && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {}
    final t = body.trim();
    if (t.length > 200) return '${t.substring(0, 200)}…';
    return t.isEmpty ? '（空响应体）' : t;
  }

  /// Sends a minimal chat request using [provider], [baseUrl], [apiKey], and [model]
  /// (e.g. current form values — does not read [LlmPrefsStore]).
  ///
  /// Returns a short human-readable success line for UI.
  static Future<String> verifyConnection({
    required LlmProviderKind provider,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final b = baseUrl.trim();
    final k = apiKey.trim();
    final m = model.trim();
    if (b.isEmpty || k.isEmpty || m.isEmpty) {
      throw const LlmDiaryTaggerException('请先填写 Base URL、模型与 API Key');
    }
    switch (provider) {
      case LlmProviderKind.openAiCompatible:
        return _verifyOpenAiChat(uri: _openAiChatUri(b), apiKey: k, model: m);
      case LlmProviderKind.anthropic:
        return _verifyAnthropicMessages(uri: _anthropicMessagesUri(b), apiKey: k, model: m);
    }
  }

  static Future<String> _verifyOpenAiChat({
    required Uri uri,
    required String apiKey,
    required String model,
  }) async {
    final payload = jsonEncode({
      'model': model,
      'max_tokens': 24,
      'temperature': 0,
      'messages': [
        {'role': 'user', 'content': '只回复两个大写字母：OK'},
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
      throw LlmDiaryTaggerException(
        'HTTP ${res.statusCode}：${_briefApiError(res.body)}',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    Map<String, dynamic> map;
    try {
      map = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const LlmDiaryTaggerException('响应不是合法 JSON');
    }
    final choices = map['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmDiaryTaggerException(
        '响应中无 choices：${_briefApiError(res.body)}',
        body: res.body,
      );
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const LlmDiaryTaggerException('choices[0] 格式异常');
    }
    final msg = first['message'];
    if (msg is! Map<String, dynamic>) {
      throw const LlmDiaryTaggerException('message 格式异常');
    }
    final content = msg['content'];
    final snippet = switch (content) {
      final String s => s.trim(),
      _ => '',
    };
    if (snippet.isEmpty) {
      throw const LlmDiaryTaggerException('模型未返回文本内容');
    }
    final short = snippet.length > 80 ? '${snippet.substring(0, 80)}…' : snippet;
    return '连接成功，已收到回复：$short';
  }

  static Future<String> _verifyAnthropicMessages({
    required Uri uri,
    required String apiKey,
    required String model,
  }) async {
    final payload = jsonEncode({
      'model': model,
      'max_tokens': 24,
      'messages': [
        {
          'role': 'user',
          'content': '只回复两个大写字母：OK',
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
      throw LlmDiaryTaggerException(
        'HTTP ${res.statusCode}：${_briefApiError(res.body)}',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    Map<String, dynamic> map;
    try {
      map = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const LlmDiaryTaggerException('响应不是合法 JSON');
    }
    final content = map['content'];
    if (content is! List || content.isEmpty) {
      throw LlmDiaryTaggerException(
        '响应中无 content：${_briefApiError(res.body)}',
        body: res.body,
      );
    }
    final block = content.first;
    if (block is! Map<String, dynamic>) {
      throw const LlmDiaryTaggerException('content[0] 格式异常');
    }
    final text = block['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const LlmDiaryTaggerException('模型未返回文本');
    }
    final snippet = text.trim();
    final short = snippet.length > 80 ? '${snippet.substring(0, 80)}…' : snippet;
    return '连接成功，已收到回复：$short';
  }

  static DiaryTaggingResult _parseTaggingJson(String raw) {
    final t = _stripJsonFences(raw);
    final decoded = jsonDecode(t);
    if (decoded is! Map<String, dynamic>) {
      throw const LlmDiaryTaggerException('模型返回不是 JSON 对象');
    }
    final title = (decoded['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) {
      throw const LlmDiaryTaggerException('模型未返回 title');
    }
    if (title.contains('|') || title.contains('\n')) {
      throw const LlmDiaryTaggerException('标题包含非法字符');
    }
    final tagsRaw = decoded['tags'];
    final tags = <String>[];
    if (tagsRaw is List) {
      for (final e in tagsRaw) {
        if (e is! String) continue;
        var x = e.trim();
        if (x.isEmpty) continue;
        if (!x.startsWith('#')) x = '#$x';
        tags.add(x);
      }
    }
    if (tags.isEmpty) {
      throw const LlmDiaryTaggerException('模型未返回有效 tags');
    }
    return DiaryTaggingResult(title: title, tags: tags);
  }

  static Future<DiaryTaggingResult> tagDiaryBody(String body) async {
    final provider = await LlmPrefsStore.readProvider();
    final baseUrl = (await LlmPrefsStore.readBaseUrl()).trim();
    final apiKey = (await LlmPrefsStore.readApiKey()).trim();
    final model = (await LlmPrefsStore.readModel()).trim();
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      throw const LlmDiaryTaggerException(
        '请先在设置中填写大模型 API 地址、API Key 与模型名称',
      );
    }

    final userContent = '日记正文如下：\n\n$body';

    switch (provider) {
      case LlmProviderKind.openAiCompatible:
        return _tagOpenAiCompatible(
          uri: _openAiChatUri(baseUrl),
          apiKey: apiKey,
          model: model,
          userContent: userContent,
        );
      case LlmProviderKind.anthropic:
        return _tagAnthropic(
          uri: _anthropicMessagesUri(baseUrl),
          apiKey: apiKey,
          model: model,
          userContent: userContent,
        );
    }
  }

  static Future<DiaryTaggingResult> _tagOpenAiCompatible({
    required Uri uri,
    required String apiKey,
    required String model,
    required String userContent,
  }) async {
    final body = jsonEncode({
      'model': model,
      'temperature': 0.3,
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
      body: body,
    );
    if (res.statusCode != 200) {
      throw LlmDiaryTaggerException(
        'OpenAI 兼容接口错误 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = map['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmDiaryTaggerException('响应中无 choices');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const LlmDiaryTaggerException('choices 格式异常');
    }
    final msg = first['message'];
    if (msg is! Map<String, dynamic>) {
      throw const LlmDiaryTaggerException('message 格式异常');
    }
    final content = msg['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const LlmDiaryTaggerException('模型未返回文本内容');
    }
    return _parseTaggingJson(content);
  }

  static Future<DiaryTaggingResult> _tagAnthropic({
    required Uri uri,
    required String apiKey,
    required String model,
    required String userContent,
  }) async {
    final body = jsonEncode({
      'model': model,
      'max_tokens': 1024,
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
      body: body,
    );
    if (res.statusCode != 200) {
      throw LlmDiaryTaggerException(
        'Anthropic 接口错误 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final content = map['content'];
    if (content is! List || content.isEmpty) {
      throw const LlmDiaryTaggerException('响应中无 content');
    }
    final block = content.first;
    if (block is! Map<String, dynamic>) {
      throw const LlmDiaryTaggerException('content 块格式异常');
    }
    final text = block['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const LlmDiaryTaggerException('模型未返回文本');
    }
    return _parseTaggingJson(text);
  }
}
