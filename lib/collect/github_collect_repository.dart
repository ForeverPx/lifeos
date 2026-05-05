import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/github_repo_prefs.dart';
import '../config/github_token.dart';
import 'collect_cache.dart';

class GithubCollectRepository {
  GithubCollectRepository({String? token}) : _token = token ?? GitHubToken.value;

  static const basePrefix = 'collect';
  static const mediaPrefix = '$basePrefix/media';

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

  Map<String, String> get _jsonHeaders => {
        ..._headers,
        'Content-Type': 'application/json',
      };

  Uri _contentsUri(String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    final o = GitHubRepoPrefs.owner;
    final r = GitHubRepoPrefs.repo;
    return Uri.parse('https://api.github.com/repos/$o/$r/contents/$encoded');
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

  /// Uploads a binary file to `collect/media/...` via GitHub Contents API,
  /// returns a `download_url` that can be embedded in markdown images.
  Future<({String path, String downloadUrl})> uploadCollectMediaBytes({
    required String fileName,
    required List<int> bytes,
    required String message,
    String? subdir,
  }) async {
    final safeName = fileName.trim().isEmpty ? 'media.bin' : fileName.trim();
    final dir = [
      mediaPrefix,
      if (subdir != null && subdir.trim().isNotEmpty) subdir.trim(),
    ].join('/');
    final path = '$dir/$safeName';
    final uri = _contentsUri(path);

    final putRes = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'message': message.trim().isEmpty ? 'lifeos: upload media' : message.trim(),
        'content': base64Encode(bytes),
      }),
    );
    if (putRes.statusCode != 200 && putRes.statusCode != 201) {
      throw GithubCollectException(
        '上传图片失败 (${putRes.statusCode}) · ${_apiMessage(putRes.body)}',
        statusCode: putRes.statusCode,
        body: putRes.body,
      );
    }
    final map = jsonDecode(putRes.body) as Map<String, dynamic>;
    final content = map['content'];
    if (content is Map<String, dynamic>) {
      final downloadUrl = content['download_url'] as String?;
      if (downloadUrl != null && downloadUrl.trim().isNotEmpty) {
        return (path: path, downloadUrl: downloadUrl.trim());
      }
    }
    final o = GitHubRepoPrefs.owner;
    final r = GitHubRepoPrefs.repo;
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final guessed = 'https://raw.githubusercontent.com/$o/$r/main/$encodedPath';
    return (path: path, downloadUrl: guessed);
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

  /// Creates a new text file under `collect/<yyyy-MM-dd>/`. Fails if the path already exists.
  Future<void> createCollectMarkdownFile({
    required DateTime day,
    required String fileName,
    required String utf8Content,
  }) async {
    final name = _assertValidCollectFileName(fileName);
    final folder = _dayFolder(day);
    final path = '$basePrefix/$folder/$name';
    final uri = _contentsUri(path);

    final getRes = await http.get(uri, headers: _headers);
    if (getRes.statusCode == 200) {
      throw GithubCollectException(
        '该日期下已存在同名文件：$name，请修改文件名后重试',
        statusCode: getRes.statusCode,
        body: getRes.body,
      );
    }
    if (getRes.statusCode != 404) {
      throw GithubCollectException(
        '检查文件是否已存在失败 (${getRes.statusCode}) · ${_apiMessage(getRes.body)}',
        statusCode: getRes.statusCode,
        body: getRes.body,
      );
    }

    final putRes = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'message': 'lifeos: 新增收藏 $folder/$name',
        'content': base64Encode(utf8.encode(utf8Content.replaceAll('\r\n', '\n'))),
      }),
    );
    if (putRes.statusCode != 200 && putRes.statusCode != 201) {
      throw GithubCollectException(
        '写入收藏失败 (${putRes.statusCode}) · ${_apiMessage(putRes.body)}',
        statusCode: putRes.statusCode,
        body: putRes.body,
      );
    }
  }

  /// Deletes a file at [path] (must be under [basePrefix]). Fetches current `sha` first.
  Future<void> deleteCollectFile({required String path}) async {
    if (!path.startsWith('$basePrefix/')) {
      throw const GithubCollectException('无效的收藏路径');
    }
    final uri = _contentsUri(path);
    final getRes = await http.get(uri, headers: _headers);
    if (getRes.statusCode == 404) {
      throw const GithubCollectException('文件已不存在或已被删除');
    }
    if (getRes.statusCode != 200) {
      throw GithubCollectException(
        '读取文件以删除失败 (${getRes.statusCode}) · ${_apiMessage(getRes.body)}',
        statusCode: getRes.statusCode,
        body: getRes.body,
      );
    }
    final map = jsonDecode(getRes.body) as Map<String, dynamic>;
    final sha = map['sha'] as String?;
    if (sha == null || sha.isEmpty) {
      throw const GithubCollectException('无法取得文件 sha，删除已取消');
    }

    final delRes = await http.delete(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'message': 'lifeos: 删除收藏 ${path.split('/').last}',
        'sha': sha,
      }),
    );
    if (delRes.statusCode != 200) {
      throw GithubCollectException(
        '删除收藏失败 (${delRes.statusCode}) · ${_apiMessage(delRes.body)}',
        statusCode: delRes.statusCode,
        body: delRes.body,
      );
    }
    await CollectCache.removeFile(path);
  }

  String _assertValidCollectFileName(String fileName) {
    var t = fileName.trim();
    if (t.isEmpty) {
      throw const GithubCollectException('文件名为空');
    }
    if (t.contains('/') || t.contains('\\') || t.contains('..')) {
      throw const GithubCollectException('文件名不能包含路径或 ..');
    }
    if (t.startsWith('.')) {
      throw const GithubCollectException('文件名不能以 . 开头');
    }
    if (!_isTextLike(t)) {
      throw const GithubCollectException('文件名须以 .md、.markdown 或 .txt 结尾');
    }
    return t;
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

