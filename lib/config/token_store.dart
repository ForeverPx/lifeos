import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStore {
  TokenStore._();

  static const _key = 'github_token';

  static Future<String> readGitHubToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key) ?? '';
    }
    const storage = FlutterSecureStorage();
    return (await storage.read(key: _key)) ?? '';
  }

  static Future<void> writeGitHubToken(String token) async {
    final normalized = token.trim();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      if (normalized.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, normalized);
      }
      return;
    }
    const storage = FlutterSecureStorage();
    if (normalized.isEmpty) {
      await storage.delete(key: _key);
    } else {
      await storage.write(key: _key, value: normalized);
    }
  }
}

