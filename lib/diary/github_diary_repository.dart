import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/github_repo_prefs.dart';
import '../config/github_token.dart';
import 'diary_cache.dart';
import 'diary_models.dart';
import 'diary_parser.dart';

class GithubDiaryRepository {
  GithubDiaryRepository({String? token}) : _token = token ?? GitHubToken.value;

  static const basePrefix = 'daily_notes';
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
        'User-Agent': 'lifeos-diary',
      };

  Map<String, String> get _jsonHeaders => {
        ..._headers,
        'Content-Type': 'application/json',
      };

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

  Uri _contentsUri(String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    final o = GitHubRepoPrefs.owner;
    final r = GitHubRepoPrefs.repo;
    return Uri.parse(
      'https://api.github.com/repos/$o/$r/contents/$encoded',
    );
  }

  /// Uploads a binary file to `daily_notes/media/...` via GitHub Contents API,
  /// returns a `download_url` that can be embedded in markdown images.
  ///
  /// The returned url is typically like:
  /// `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>`
  Future<({String path, String downloadUrl})> uploadDiaryMediaBytes({
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
      throw GithubDiaryException(
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
    // Fallback: construct a raw URL with a best-effort branch guess.
    final o = GitHubRepoPrefs.owner;
    final r = GitHubRepoPrefs.repo;
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final guessed = 'https://raw.githubusercontent.com/$o/$r/main/$encodedPath';
    return (path: path, downloadUrl: guessed);
  }

  /// Returns which days in [year]-[month] have a `.md` file (1–31).
  Future<Set<int>> listDaysWithEntries(int year, int month) async {
    final m = month.toString().padLeft(2, '0');
    final uri = _contentsUri('$basePrefix/$year/$m');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) {
      // Month directory not existing is expected when there are no entries yet.
      return {};
    }
    if (res.statusCode != 200) {
      throw GithubDiaryException(
        '列出目录失败 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    final days = <int>{};
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final name = item['name'] as String?;
      if (name == null || !name.endsWith('.md')) continue;
      final dayStr = name.substring(0, name.length - 3);
      final d = int.tryParse(dayStr);
      if (d != null && d >= 1 && d <= 31) days.add(d);
    }
    return days;
  }

  Future<List<DiaryEntry>> fetchDay(
    int year,
    int month,
    int day, {
    bool assumeExists = false,
    bool allowNotFound = false,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(year, month, day);
    final isBeforeToday = selected.isBefore(today);
    if (isBeforeToday) {
      final cached = await DiaryCache.getDayMarkdown(
        year: year,
        month: month,
        day: day,
      );
      if (cached != null) {
        return parseDiaryMarkdown(cached);
      }
    }

    final y = year.toString();
    final m = month.toString().padLeft(2, '0');
    final dPadded = day.toString().padLeft(2, '0');
    final dRaw = day.toString();
    final fileNames = <String>{'$dPadded.md', '$dRaw.md'}.toList();

    for (final fileName in fileNames) {
      final uri = _contentsUri('$basePrefix/$y/$m/$fileName');
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 404) continue;
      if (res.statusCode != 200) {
        throw GithubDiaryException(
          '读取日记失败 (${res.statusCode})',
          statusCode: res.statusCode,
          body: res.body,
        );
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final encoding = map['encoding'] as String?;
      final content = map['content'] as String?;
      if (encoding != 'base64' || content == null) {
        throw const GithubDiaryException('意外的 API 响应格式');
      }
      final bytes = base64.decode(
        content.replaceAll('\n', ''),
      );
      final text = utf8.decode(bytes);
      await DiaryCache.setDayMarkdown(
        year: year,
        month: month,
        day: day,
        markdown: text,
      );
      return parseDiaryMarkdown(text);
    }

    if (allowNotFound) return [];
    if (assumeExists) {
      throw const GithubDiaryException(
        '索引显示该日期有日记，但文件未找到（404）。请刷新月份或检查该日文件命名。',
      );
    }
    return [];
  }

  /// Appends [markdownBlock] to the day's `.md` file (creates file if missing).
  Future<void> appendDiaryMarkdown({
    required int year,
    required int month,
    required int day,
    required String markdownBlock,
  }) async {
    final y = year.toString();
    final m = month.toString().padLeft(2, '0');
    final dPadded = day.toString().padLeft(2, '0');
    final path = '$basePrefix/$y/$m/$dPadded.md';
    final uri = _contentsUri(path);

    final getRes = await http.get(uri, headers: _headers);
    String existing = '';
    String? sha;
    if (getRes.statusCode == 200) {
      final map = jsonDecode(getRes.body) as Map<String, dynamic>;
      sha = map['sha'] as String?;
      final encoding = map['encoding'] as String?;
      final content = map['content'] as String?;
      if (encoding != 'base64' || content == null || sha == null || sha.isEmpty) {
        throw const GithubDiaryException('读取现有日记文件时响应格式异常');
      }
      final bytes = base64.decode(content.replaceAll('\n', ''));
      existing = utf8.decode(bytes);
    } else if (getRes.statusCode != 404) {
      throw GithubDiaryException(
        '读取日记文件失败 (${getRes.statusCode}) · ${_apiMessage(getRes.body)}',
        statusCode: getRes.statusCode,
        body: getRes.body,
      );
    }

    final block = markdownBlock.trim();
    final merged = existing.trim().isEmpty
        ? block
        : '${existing.trim()}\n\n$block';

    final bodyMap = <String, dynamic>{
      'message': 'lifeos: 新增日记 $y-$m-$dPadded',
      'content': base64Encode(utf8.encode(merged)),
    };
    if (sha != null && sha.isNotEmpty) {
      bodyMap['sha'] = sha;
    }

    final putRes = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(bodyMap),
    );
    if (putRes.statusCode != 200 && putRes.statusCode != 201) {
      throw GithubDiaryException(
        '写入日记失败 (${putRes.statusCode}) · ${_apiMessage(putRes.body)}',
        statusCode: putRes.statusCode,
        body: putRes.body,
      );
    }

    await DiaryCache.setDayMarkdown(
      year: year,
      month: month,
      day: day,
      markdown: merged,
    );
  }

  /// Reads the day `.md` file that exists on GitHub (tries `DD.md` then `D.md`).
  Future<({String path, String utf8, String sha})?> _readExistingDayFile(
    int year,
    int month,
    int day,
  ) async {
    final y = year.toString();
    final m = month.toString().padLeft(2, '0');
    final dPadded = day.toString().padLeft(2, '0');
    final dRaw = day.toString();
    for (final fileName in <String>['$dPadded.md', '$dRaw.md']) {
      final path = '$basePrefix/$y/$m/$fileName';
      final uri = _contentsUri(path);
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 404) continue;
      if (res.statusCode != 200) {
        throw GithubDiaryException(
          '读取日记失败 (${res.statusCode})',
          statusCode: res.statusCode,
          body: res.body,
        );
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final encoding = map['encoding'] as String?;
      final content = map['content'] as String?;
      final sha = map['sha'] as String?;
      if (encoding != 'base64' || content == null || sha == null || sha.isEmpty) {
        throw const GithubDiaryException('意外的 API 响应格式');
      }
      final bytes = base64.decode(content.replaceAll('\n', ''));
      final text = utf8.decode(bytes);
      return (path: path, utf8: text, sha: sha);
    }
    return null;
  }

  /// Removes one diary block identified by [headerLine] (same as [DiaryEntry.headerLine]).
  Future<void> removeDiaryEntry({
    required int year,
    required int month,
    required int day,
    required String headerLine,
  }) async {
    final snap = await _readExistingDayFile(year, month, day);
    if (snap == null) {
      throw const GithubDiaryException('该日没有日记文件');
    }

    final next = removeDiaryBlockByHeaderLine(snap.utf8, headerLine);
    if (next == null) {
      throw const GithubDiaryException('未找到要删除的条目');
    }

    final uri = _contentsUri(snap.path);
    if (next.trim().isEmpty) {
      final delRes = await http.delete(
        uri,
        headers: _jsonHeaders,
        body: jsonEncode({
          'message': 'lifeos: 删除日记 ${snap.path.split('/').last}',
          'sha': snap.sha,
        }),
      );
      if (delRes.statusCode != 200) {
        throw GithubDiaryException(
          '删除文件失败 (${delRes.statusCode}) · ${_apiMessage(delRes.body)}',
          statusCode: delRes.statusCode,
          body: delRes.body,
        );
      }
      await DiaryCache.removeDay(year: year, month: month, day: day);
      return;
    }

    final putRes = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'message': 'lifeos: 删除日记条目',
        'content': base64Encode(utf8.encode(next)),
        'sha': snap.sha,
      }),
    );
    if (putRes.statusCode != 200 && putRes.statusCode != 201) {
      throw GithubDiaryException(
        '更新日记失败 (${putRes.statusCode}) · ${_apiMessage(putRes.body)}',
        statusCode: putRes.statusCode,
        body: putRes.body,
      );
    }
    await DiaryCache.setDayMarkdown(
      year: year,
      month: month,
      day: day,
      markdown: next,
    );
  }
}

class GithubDiaryException implements Exception {
  const GithubDiaryException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => message;
}
