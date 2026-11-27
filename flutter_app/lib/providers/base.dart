/// Shared provider base behavior, ported from the C++ `providers.cpp`:
/// base snapshot construction, API key retrieval, `JoinUrl`, HTTP success
/// mapping with the error table, and `Retry-After` parsing.
library;

import '../config/settings.dart';
import '../domain/decimal.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import 'provider_exception.dart';

/// Converts a JSON numeric/string value to an exact decimal string with the
/// reference's `NumberText` rules: strings must be decimals, integers are
/// printed verbatim, floats are fixed-6 with trailing zeros stripped.
String numberText(Object? value) {
  if (value is String) {
    if (!isDecimal(value)) {
      throw ProviderException(
        ProviderError('invalid-number', 'expected decimal string', transient: false),
      );
    }
    return value;
  }
  if (value is int) {
    return value.toString();
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ProviderException(
        ProviderError('invalid-number', 'non-finite numeric value', transient: false),
      );
    }
    var text = value.toStringAsFixed(6);
    while (text.isNotEmpty && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text.isEmpty ? '0' : text;
  }
  throw ProviderException(
    ProviderError('invalid-number', 'expected numeric value', transient: false),
  );
}

/// Builds the fresh/healthy snapshot shell shared by all adapters.
ProviderSnapshot baseSnapshot(ProviderConfig config, DateTime observedAt) {
  final snapshot = ProviderSnapshot();
  snapshot.providerId = config.id;
  snapshot.displayName = config.name;
  snapshot.kind = config.kind;
  snapshot.observedAt = observedAt;
  snapshot.freshness = Freshness.fresh;
  snapshot.health = Health.healthy;
  return snapshot;
}

/// Builds the `unsupported` placeholder metric used for unavailable figures.
Metric unsupported(
  MetricKind kind,
  MetricUnit unit,
  MetricScope scope,
  String label,
) => Metric(
      kind: kind,
      value: '',
      unit: unit,
      scope: scope,
      provenance: Provenance.providerReported,
      availability: Availability.unsupported,
      label: label,
    );

/// Joins a base URL and a route with the reference's same-origin rules.
String joinUrl(String base, String path) {
  if (path.length > 2048 || path.contains('://')) {
    throw ProviderException(
      ProviderError(
        'invalid-route',
        'provider route must be a bounded same-origin path',
        transient: false,
      ),
    );
  }
  var trimmed = base;
  while (trimmed.isNotEmpty && trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  var normalized = path;
  if (normalized.isEmpty || !normalized.startsWith('/')) {
    normalized = '/$normalized';
  }
  return trimmed + normalized;
}

/// Parses the `Retry-After` header value in seconds, when positive.
Duration? parseRetryAfter(HttpResponse response) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == 'retry-after') {
      final seconds = int.tryParse(entry.value.trim());
      if (seconds != null && seconds > 0) return Duration(seconds: seconds);
      return null;
    }
  }
  return null;
}

/// Maps non-2xx responses onto the reference's HTTP error table.
void requireHttpSuccess(HttpResponse response) {
  if (response.status >= 200 && response.status < 300) return;
  if (response.status == 401 || response.status == 403) {
    throw ProviderException(
      ProviderError('unauthorized', 'authentication rejected', transient: false),
    );
  }
  if (response.status == 429) {
    throw ProviderException(
      ProviderError('rate-limited', 'rate limited', transient: true, retryAfter: parseRetryAfter(response)),
    );
  }
  final transient = response.status >= 500;
  throw ProviderException(
    ProviderError(
      'http-${response.status}',
      'HTTP request failed with status ${response.status}',
      transient: transient,
    ),
  );
}

/// Decrypts the provider API key through the secret store.
Future<String> apiKey(ProviderConfig config, SecretStore secrets) async {
  if (config.encryptedApiKey.isEmpty) return '';
  return secrets.unprotect(config.encryptedApiKey);
}