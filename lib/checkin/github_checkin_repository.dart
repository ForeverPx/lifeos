import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/github_token.dart';
import 'checkin_global_stats.dart';
import 'checkin_models.dart';
import 'checkin_week.dart';

class GithubCheckinRepository {
  GithubCheckinRepository({String? token}) : _token = token ?? GitHubToken.value;

  static const owner = 'ForeverPx';
  static const repo = 'my-ai-memory';
  static const basePrefix = 'checkins';

  /// Global rollups for the week calendar (updated after each week save).
  static const globalStatsFilePath = '$basePrefix/_global_checkin_stats.json';

  String _token;

  bool get hasToken => _token.isNotEmpty;

  void setToken(String token) {
    _token = token.trim();
  }

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
        'User-Agent': 'lifeos-checkin',
        'Content-Type': 'application/json',
      };

  Uri _contentsUri(String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse(
      'https://api.github.com/repos/$owner/$repo/contents/$encoded',
    );
  }

  String _filePath(String weekId) => '$basePrefix/$weekId/checkin.json';

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

  /// Loads weekly check-in file; [fileSha] is null when file does not exist (404).
  Future<CheckinFileSnapshot> fetchWeek(String weekId) async {
    final path = _filePath(weekId);
    final uri = _contentsUri(path);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) {
      return CheckinFileSnapshot(
        state: WeeklyCheckinState.empty(weekId),
        fileSha: null,
      );
    }
    if (res.statusCode != 200) {
      throw GithubCheckinException(
        '读取打卡失败 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final encoding = map['encoding'] as String?;
    final content = map['content'] as String?;
    final sha = map['sha'] as String?;
    if (encoding != 'base64' || content == null || sha == null) {
      throw const GithubCheckinException('意外的 API 响应格式');
    }
    final bytes = base64.decode(content.replaceAll('\n', ''));
    final text = utf8.decode(bytes);
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) {
      throw const GithubCheckinException('打卡文件不是 JSON 对象');
    }
    return CheckinFileSnapshot(
      state: WeeklyCheckinState.fromJson(weekId, json),
      fileSha: sha,
    );
  }

  /// Loads aggregated week stats for the calendar; empty when file missing.
  Future<CheckinGlobalStatsSnapshot> fetchGlobalStats() async {
    final uri = _contentsUri(globalStatsFilePath);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) {
      return CheckinGlobalStatsSnapshot(
        document: CheckinGlobalStatsDocument.empty(),
        fileSha: null,
      );
    }
    if (res.statusCode != 200) {
      throw GithubCheckinException(
        '读取打卡统计失败 (${res.statusCode})',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final encoding = map['encoding'] as String?;
    final content = map['content'] as String?;
    final sha = map['sha'] as String?;
    if (encoding != 'base64' || content == null || sha == null) {
      throw const GithubCheckinException('意外的 API 响应格式');
    }
    final bytes = base64.decode(content.replaceAll('\n', ''));
    final text = utf8.decode(bytes);
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) {
      throw const GithubCheckinException('统计文件不是 JSON 对象');
    }
    return CheckinGlobalStatsSnapshot(
      document: CheckinGlobalStatsDocument.fromJson(json),
      fileSha: sha,
    );
  }

  Future<String> _putUtf8File({
    required String path,
    required String message,
    required String utf8Content,
    String? previousSha,
  }) async {
    final uri = _contentsUri(path);
    final bodyMap = <String, dynamic>{
      'message': message,
      'content': base64Encode(utf8.encode(utf8Content)),
    };
    if (previousSha != null && previousSha.isNotEmpty) {
      bodyMap['sha'] = previousSha;
    }
    final res = await http.put(
      uri,
      headers: _headers,
      body: jsonEncode(bodyMap),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw GithubCheckinException(
        '保存文件失败 (${res.statusCode}) · ${_apiMessage(res.body)}',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final out = jsonDecode(res.body) as Map<String, dynamic>;
    final content = out['content'] as Map<String, dynamic>?;
    final newSha = content?['sha'] as String?;
    if (newSha == null || newSha.isEmpty) {
      throw const GithubCheckinException('保存成功但未返回文件 sha');
    }
    return newSha;
  }

  /// Creates or updates [state] for [weekId], then refreshes [globalStatsFilePath].
  Future<SaveWeekOutcome> saveWeek({
    required String weekId,
    required WeeklyCheckinState state,
    String? previousSha,
  }) async {
    final path = _filePath(weekId);
    final pretty = const JsonEncoder.withIndent('  ').convert(state.toJson());
    final weekSha = await _putUtf8File(
      path: path,
      message: 'lifeos: 更新打卡 $weekId',
      utf8Content: pretty,
      previousSha: previousSha,
    );

    final bounds = CheckinWeekBounds.tryParseWeekId(weekId);
    if (bounds == null) {
      return SaveWeekOutcome(
        weekFileSha: weekSha,
        globalStatsUpdated: false,
        globalStatsError: '无法解析周标识 $weekId',
      );
    }

    try {
      final statsSnap = await fetchGlobalStats();
      final rollup = CheckinWeekRollup.fromState(state, bounds);
      final doc = statsSnap.document.upsertWeek(rollup);
      final statsJson = const JsonEncoder.withIndent('  ').convert(doc.toJson());
      final statsSha = await _putUtf8File(
        path: globalStatsFilePath,
        message: 'lifeos: 更新打卡统计 $weekId',
        utf8Content: statsJson,
        previousSha: statsSnap.fileSha,
      );
      return SaveWeekOutcome(
        weekFileSha: weekSha,
        globalStatsUpdated: true,
        globalStatsDocument: doc,
        globalStatsSha: statsSha,
      );
    } catch (e) {
      return SaveWeekOutcome(
        weekFileSha: weekSha,
        globalStatsUpdated: false,
        globalStatsError: e.toString(),
      );
    }
  }
}

class CheckinFileSnapshot {
  const CheckinFileSnapshot({
    required this.state,
    required this.fileSha,
  });

  final WeeklyCheckinState state;
  final String? fileSha;
}

class GithubCheckinException implements Exception {
  const GithubCheckinException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => message;
}
