class GitHubToken {
  // 不要把 token 写进代码或提交到仓库。
  // 通过运行参数注入：
  // - flutter run --dart-define=GITHUB_TOKEN=xxx
  // - flutter run --dart-define-from-file=dart_defines/local.json
  static const String value = String.fromEnvironment('GITHUB_TOKEN', defaultValue: '');
}

