import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which HTTP API shape to use for tagging.
enum LlmProviderKind {
  /// `POST …/chat/completions` with OpenAI-style JSON body.
  openAiCompatible,

  /// `POST …/v1/messages` with Anthropic-style JSON body.
  anthropic,
}

abstract final class LlmPrefsStore {
  LlmPrefsStore._();

  static const _keyProvider = 'llm_provider';
  static const _keyBaseUrl = 'llm_base_url';
  static const _keyModel = 'llm_model';
  static const _keyApiKey = 'llm_api_key';

  static Future<LlmProviderKind> readProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyProvider);
    if (raw == LlmProviderKind.anthropic.name) {
      return LlmProviderKind.anthropic;
    }
    return LlmProviderKind.openAiCompatible;
  }

  static Future<void> writeProvider(LlmProviderKind v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProvider, v.name);
  }

  static Future<String> readBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl) ?? '';
  }

  static Future<void> writeBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final t = url.trim();
    if (t.isEmpty) {
      await prefs.remove(_keyBaseUrl);
    } else {
      await prefs.setString(_keyBaseUrl, t);
    }
  }

  static Future<String> readModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyModel) ?? '';
  }

  static Future<void> writeModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    final t = model.trim();
    if (t.isEmpty) {
      await prefs.remove(_keyModel);
    } else {
      await prefs.setString(_keyModel, t);
    }
  }

  static Future<String> readApiKey() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyApiKey) ?? '';
    }
    const storage = FlutterSecureStorage();
    return (await storage.read(key: _keyApiKey)) ?? '';
  }

  static Future<void> writeApiKey(String apiKey) async {
    final normalized = apiKey.trim();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      if (normalized.isEmpty) {
        await prefs.remove(_keyApiKey);
      } else {
        await prefs.setString(_keyApiKey, normalized);
      }
      return;
    }
    const storage = FlutterSecureStorage();
    if (normalized.isEmpty) {
      await storage.delete(key: _keyApiKey);
    } else {
      await storage.write(key: _keyApiKey, value: normalized);
    }
  }

  static Future<bool> isConfigured() async {
    final url = (await readBaseUrl()).trim();
    final key = (await readApiKey()).trim();
    final model = (await readModel()).trim();
    return url.isNotEmpty && key.isNotEmpty && model.isNotEmpty;
  }
}
