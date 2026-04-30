import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/github_token.dart';
import 'diary_cache.dart';
import 'diary_parser.dart';
import 'diary_models.dart';

class GithubDiaryRepository {
  GithubDiaryRepository({String? token}) : _token = token ?? GitHubToken.value;

  static const owner = 'ForeverPx';
  static const repo = 'my-ai-memory';
  static const basePrefix = 'daily_notes';

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

  Uri _contentsUri(String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse(
      'https://api.github.com/repos/$owner/$repo/contents/$encoded',
    );
  }

  String _apiMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'] as String?;
        if (msg != null && msg.trim().isNotEmpty) {
          return msg.trim();
        }
      }
    } catch (_) {
      // Ignore parse errors and fallback to raw body.
    }
    final raw = body.trim();
    if (raw.isEmpty) return 'unknown';
    return raw.length > 120 ? '${raw.substring(0, 120)}...' : raw;
  }

  /// Returns which days in [year]-[month] have a `.md` file (1–31).
  Future<Set<int>> listDaysWithEntries(int year, int month) async {
    final m = month.toString().padLeft(2, '0');
    final uri = _contentsUri('$basePrefix/$year/$m');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) {
      if (_token.isNotEmpty) {
        throw GithubDiaryException(
          '无法访问日记目录：可能 token 无权限或仓库不可用（404）'
          ' · ${_apiMessage(res.body)}',
          statusCode: res.statusCode,
          body: res.body,
        );
      }
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
    final d = day.toString().padLeft(2, '0');
    final uri = _contentsUri('$basePrefix/$y/$m/$d.md');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) {
      if (allowNotFound) return [];
      if (_token.isNotEmpty && assumeExists) {
        throw GithubDiaryException(
          '读取失败：文件可能存在但无法访问（404），'
          '请检查 token 是否有仓库读取权限 · ${_apiMessage(res.body)}',
          statusCode: res.statusCode,
          body: res.body,
        );
      }
      if (_token.isNotEmpty) {
        throw GithubDiaryException(
          '读取日记失败（404）：该日期可能没有文件，'
          '或当前 token 无法访问该文件 · ${_apiMessage(res.body)}',
          statusCode: res.statusCode,
          body: res.body,
        );
      }
      return [];
    }
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
}

class GithubDiaryException implements Exception {
  const GithubDiaryException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => message;
}
