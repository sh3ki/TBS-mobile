class AppConfig {
  // Default to production API; override via --dart-define for local testing.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://tbscontainermnl.com/api',
  );

  static const Duration requestTimeout = Duration(seconds: 25);

  static Uri uri(String path, [Map<String, String>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalizedPath');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: query);
  }
}
