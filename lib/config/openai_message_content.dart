import 'dart:convert';

/// Some gateways wrap the standard object in `data` / `result` / `response`.
Map<String, dynamic> unwrapOpenAiChatResponseMap(Map<String, dynamic> top) {
  if (top['choices'] is List) return top;
  for (final key in ['data', 'result', 'response']) {
    final inner = top[key];
    if (inner is Map) {
      final m = Map<String, dynamic>.from(inner);
      if (m['choices'] is List) return m;
    }
  }
  return top;
}

/// Parses `choices[n].message.content` from OpenAI-compatible chat APIs.
///
/// Handles: plain string; multimodal arrays like `[{"type":"text","text":"..."}]`;
/// newer blocks with `type: output_text`; single Map blocks; [parsed] is handled
/// in [openAiAssistantTextFromChoice].
String? openAiAssistantMessageText(dynamic content) {
  if (content == null) return null;
  if (content is String) {
    final s = content.trim();
    return s.isEmpty ? null : s;
  }
  if (content is Map) {
    final m = Map<String, dynamic>.from(content);
    for (final key in ['text', 'value', 'output']) {
      final v = m[key];
      if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is String) {
        final s = item.trim();
        if (s.isNotEmpty) parts.add(s);
      } else if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        String? piece;
        final text = m['text'];
        if (text is String && text.trim().isNotEmpty) {
          piece = text.trim();
        } else {
          for (final key in ['value', 'output', 'content']) {
            final v = m[key];
            if (v is String && v.trim().isNotEmpty) {
              piece = v.trim();
              break;
            }
          }
        }
        if (piece != null) parts.add(piece);
      }
    }
    if (parts.isEmpty) return null;
    return parts.join();
  }
  return null;
}

/// Reads assistant-visible text from one `choices[]` item (OpenAI chat/completions).
///
/// Order: `message.content` → `message.parsed` (JSON) → `message.reasoning_content`
/// (智谱 GLM 等) → legacy `text` → `delta.content`.
String? openAiAssistantTextFromChoice(dynamic choiceRaw) {
  if (choiceRaw is! Map) return null;
  final choice = Map<String, dynamic>.from(choiceRaw);

  final msg = choice['message'];
  if (msg is String) {
    final s = msg.trim();
    if (s.isNotEmpty) return s;
  }
  if (msg is Map) {
    final msgMap = Map<String, dynamic>.from(msg);

    var t = openAiAssistantMessageText(msgMap['content']);
    if (t != null && t.isNotEmpty) return t;

    final parsed = msgMap['parsed'];
    if (parsed != null) {
      try {
        return jsonEncode(parsed);
      } catch (_) {}
    }

    for (final key in ['reasoning_content', 'reasoning']) {
      final v = msgMap[key];
      if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty) return s;
      }
    }
  }

  final legacy = choice['text'];
  if (legacy is String && legacy.trim().isNotEmpty) return legacy.trim();

  final delta = choice['delta'];
  if (delta is Map) {
    final deltaMap = Map<String, dynamic>.from(delta);
    final t = openAiAssistantMessageText(deltaMap['content']);
    if (t != null && t.isNotEmpty) return t;
  }

  return null;
}

/// Human-readable hint when the assistant returned [tool_calls] instead of text.
String? openAiToolCallsBlockingHint(dynamic choiceRaw) {
  if (choiceRaw is! Map) return null;
  final choice = Map<String, dynamic>.from(choiceRaw);
  final msg = choice['message'];
  if (msg is! Map) return null;
  final msgMap = Map<String, dynamic>.from(msg);
  if (msgMap['tool_calls'] != null) {
    return '模型返回了 tool_calls 而非普通文本，请在网关关闭函数调用或改用不支持工具的模型';
  }
  return null;
}

/// Truncated one-line body for user-visible error messages.
String briefOpenAiResponseForError(String body) {
  final t = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return '（空响应体）';
  if (t.length <= 200) return t;
  return '${t.substring(0, 200)}…';
}
