/// InfinityFree API Configuration for Mobile Gate Scanner
class ApiConstants {
  /// Active InfinityFree live domain
  static String baseUrl = 'http://ncstparking-test.rf.gd/api';

  static const String vehiclesEndpoint = '/vehicles.php';
  static const String logsEndpoint = '/logs.php';
  static const String statsEndpoint = '/stats.php';
  static const String incidentsEndpoint = '/incidents.php';

  static const Duration timeout = Duration(seconds: 8);

  static Map<String, String> defaultHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'User-Agent': 'SecurePark-GateScanner/2.4',
    'X-Requested-With': 'XMLHttpRequest',
  };

  /// Root host URL (excluding the /api suffix)
  static String get hostUrl => baseUrl.replaceAll(RegExp(r'/api/?$'), '');

  /// Resolve any image string (full URL, relative server path, base64 data URI, or asset)
  static String resolveImageUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('assets/')) {
      return trimmed;
    }
    final cleanHost = hostUrl;
    if (trimmed.startsWith('/')) {
      return '$cleanHost$trimmed';
    }
    return '$cleanHost/$trimmed';
  }
}
