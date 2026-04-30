import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/github_token.dart';
import 'collect_cache.dart';

class GithubCollectRepository {
  GithubCollectRepository({String? token}) : _token = token ?? GitHubToken.value;

  static const owner = 'ForeverPx';
  static const repo = 'my-ai-memory';
  static const basePrefix = 'collect';

  String _token;

  bool get hasToken => _token.isNotEmpty;

  void setToken(String token) {
    _token = token.trim();
  }

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
        'User-Agent': 'lifeos-collect',
      };

  Uri _contentsUri(String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$encoded');
  }

  String _apiMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'] as String?;
        if (msg != null && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {}
    final raw = body.trim();
    if (raw.isEmpty) return 'unknown';
    return raw.length > 120 ? '${raw.substring(0, 120)}...' : raw;
  }

  Future<List<DateTime>> listDays({int limit = 120}) async {
    final uri = _contentsUri(basePrefix);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) {
      if (_token.isNotEmpty) {
        throw GithubCollectException(
          '无法访问收藏目录：可能 token 无权限或仓库不可用（404）'
          ' · ${_apiMessage(res.body)}',
          statusCode: res.statusCode,
          body: res.body,
        );
      }
      return [];
    }
    if (res.statusCode != 200) {
      throw GithubCollectException(
        '列出收藏目录失败 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }

    final list = jsonDecode(res.body) as List<dynamic>;
    final out = <DateTime>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type'] != 'dir') continue;
      final name = item['name'] as String?;
      if (name == null) continue;
      final d = DateTime.tryParse(name);
      if (d == null) continue;
      out.add(DateTime(d.year, d.month, d.day));
    }

    out.sort((a, b) => b.compareTo(a)); // newest first
    if (out.length > limit) return out.sublist(0, limit);
    return out;
  }

  Future<List<GithubCollectFile>> listFilesForDay(DateTime day) async {
    final dayName = _dayFolder(day);
    final uri = _contentsUri('$basePrefix/$dayName');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) return [];
    if (res.statusCode != 200) {
      throw GithubCollectException(
        '列出收藏文件失败 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    final out = <GithubCollectFile>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type'] != 'file') continue;
      final name = item['name'] as String?;
      final path = item['path'] as String?;
      final sha = item['sha'] as String?;
      if (name == null || path == null || sha == null) continue;
      if (!_isTextLike(name)) continue;
      out.add(GithubCollectFile(name: name, path: path, sha: sha));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<String> fetchFileContent({
    required String path,
    required String sha,
    bool allowCache = true,
  }) async {
    if (allowCache) {
      final cached = await CollectCache.getFile(path);
      if (cached != null && cached.sha == sha) {
        return cached.content;
      }
    }

    final uri = _contentsUri(path);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) {
      return '';
    }
    if (res.statusCode != 200) {
      throw GithubCollectException(
        '读取收藏失败 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final encoding = map['encoding'] as String?;
    final content = map['content'] as String?;
    final serverSha = map['sha'] as String?;
    if (encoding != 'base64' || content == null) {
      throw const GithubCollectException('意外的 API 响应格式');
    }
    final bytes = base64.decode(content.replaceAll('\n', ''));
    final text = utf8.decode(bytes);
    final toStoreSha = serverSha ?? sha;
    await CollectCache.setFile(path: path, sha: toStoreSha, content: text);
    return text;
  }

  String _dayFolder(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isTextLike(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.md') ||
        lower.endsWith('.markdown') ||
        lower.endsWith('.txt');
  }
}

class GithubCollectFile {
  const GithubCollectFile({
    required this.name,
    required this.path,
    required this.sha,
  });

  final String name;
  final String path;
  final String sha;
}

class GithubCollectException implements Exception {
  const GithubCollectException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => message;
}

