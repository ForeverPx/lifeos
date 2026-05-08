/// GitHub Contents API returns [download_url] values that often include a
/// short-lived `?token=...` query string. After roughly a day those tokens
/// expire and `raw.githubusercontent.com` responds with 404.
///
/// Public repositories serve the same bytes at the URL without any query.
///
/// Private repositories may still require authenticated access to raw files;
/// stripping the token alone is not sufficient there (see GitHub docs).
String stableGithubRawUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host != 'raw.githubusercontent.com') return trimmed;
  if (!uri.hasQuery) return trimmed;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    fragment: uri.fragment.isEmpty ? null : uri.fragment,
  ).toString();
}

class GithubImageRequest {
  const GithubImageRequest({required this.url, this.headers});

  final String url;
  final Map<String, String>? headers;
}

GithubImageRequest githubImageRequest(String url, {required String token}) {
  final stableUrl = stableGithubRawUrl(url);
  final trimmedToken = token.trim();
  final rawUri = Uri.tryParse(stableUrl);
  final apiUri = _rawGithubUriToContentsApiUri(rawUri);

  if (apiUri == null || trimmedToken.isEmpty) {
    return GithubImageRequest(url: stableUrl);
  }

  return GithubImageRequest(
    url: apiUri.toString(),
    headers: {
      'Accept': 'application/vnd.github.raw',
      'X-GitHub-Api-Version': '2022-11-28',
      'Authorization': 'Bearer $trimmedToken',
      'User-Agent': 'lifeos',
    },
  );
}

Uri? _rawGithubUriToContentsApiUri(Uri? uri) {
  if (uri == null || uri.host != 'raw.githubusercontent.com') return null;

  final segments = uri.pathSegments;
  if (segments.length < 4) return null;

  final owner = segments[0];
  final repo = segments[1];
  final branch = segments[2];
  final filePath = segments.skip(3).join('/');
  if (owner.isEmpty || repo.isEmpty || branch.isEmpty || filePath.isEmpty) {
    return null;
  }

  return Uri.https('api.github.com', '/repos/$owner/$repo/contents/$filePath', {
    'ref': branch,
  });
}
