import 'package:shared_preferences/shared_preferences.dart';

/// GitHub 数据仓库（owner / repo），日记、收藏、打卡等均读写该库。
abstract final class GitHubRepoPrefs {
  GitHubRepoPrefs._();

  static const defaultOwner = 'ForeverPx';
  static const defaultRepo = 'my-ai-memory';

  static const _keyOwner = 'github_repo_owner';
  static const _keyRepo = 'github_repo_name';

  static String _owner = defaultOwner;
  static String _repo = defaultRepo;

  static String get owner => _owner;
  static String get repo => _repo;
  static String get displayName => '$_owner/$_repo';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawO = prefs.getString(_keyOwner);
    final rawR = prefs.getString(_keyRepo);
    _owner = _effective(rawO, defaultOwner);
    _repo = _effective(rawR, defaultRepo);
  }

  /// 设置页展示：未保存过时返回内置默认值。
  static Future<String> readOwnerForEdit() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyOwner);
    if (raw == null) return defaultOwner;
    final t = raw.trim();
    return t.isEmpty ? defaultOwner : t;
  }

  static Future<String> readRepoForEdit() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRepo);
    if (raw == null) return defaultRepo;
    final t = raw.trim();
    return t.isEmpty ? defaultRepo : t;
  }

  static Future<void> writeFromUserInput(String owner, String repo) async {
    final o = _effective(owner, defaultOwner);
    final r = _effective(repo, defaultRepo);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOwner, o);
    await prefs.setString(_keyRepo, r);
    _owner = o;
    _repo = r;
  }

  static String _effective(String? raw, String fallback) {
    final t = raw?.trim() ?? '';
    return t.isEmpty ? fallback : t;
  }
}
