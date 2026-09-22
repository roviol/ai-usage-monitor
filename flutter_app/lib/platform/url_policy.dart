/// URL safety policy ported from the C++ reference: `https` is always
/// accepted, `http` only for loopback hosts when explicitly enabled.
library;

final RegExp _urlPattern = RegExp(
  r'^(https?)://(\[[^\]]+\]|[^/:?#]+)(?::[0-9]+)?(?:[/?#].*)?$',
  caseSensitive: false,
);

/// Maximum accepted HTTP response body: 1 MiB.
const int maxHttpResponseBytes = 1024 * 1024;

/// Default request timeout used by providers and transports.
const Duration defaultHttpTimeout = Duration(seconds: 10);

bool _isLoopbackHost(String host) {
  final lowered = host.toLowerCase();
  return lowered == 'localhost' || lowered == '127.0.0.1' || lowered == '[::1]' || lowered == '::1';
}

/// Whether [url] may be sent to: https always, http only for localhost,
/// 127.0.0.1, [::1] or ::1 with the provider's loopback exception enabled.
bool isSafeEndpointUrl(String url, bool allowLoopbackHttp) {
  final match = _urlPattern.firstMatch(url);
  if (match == null) return false;
  final scheme = match.group(1)!.toLowerCase();
  if (scheme == 'https') return true;
  return scheme == 'http' && allowLoopbackHttp && _isLoopbackHost(match.group(2)!);
}

/// Replaces credential material in [text] with `<redacted>` markers, mirroring
/// the reference's `RedactSecrets`.
String redactSecrets(String text, List<String> secrets) {
  var result = text;
  for (final secret in secrets) {
    if (secret.isEmpty) continue;
    var position = 0;
    while (true) {
      position = result.indexOf(secret, position);
      if (position == -1) break;
      result = result.replaceRange(position, position + secret.length, '<redacted>');
      position += 10;
    }
  }
  return result.replaceAllMapped(
    RegExp(r'(Authorization\s*:\s*)([^\r\n]+)', caseSensitive: false),
    (match) => '${match.group(1)}<redacted>',
  );
}