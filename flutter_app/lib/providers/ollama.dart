/// Ollama adapter: `/api/ps` parsing with RFC 3339 unload times, `/api/me`
/// account label, cloud `/api/usage` metrics and credential host separation
/// (local credential only to the configured base URL, cloud credential only
/// to ollama.com).
library;

import 'dart:convert';

import '../config/settings.dart';
import '../domain/decimal.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import '../platform/url_policy.dart';
import 'base.dart';
import 'provider.dart';
import 'provider_exception.dart';

const String ollamaCloudUsageUrl = 'https://ollama.com/api/usage';

/// Parses an RFC 3339 timestamp with optional fractional seconds and `Z` or
/// numeric offset, mirroring the reference's hand-written parser.
DateTime? parseOllamaUnloadTime(String text) {
  const stampLength = 19;
  if (text.length < stampLength) return null;
  if (text[4] != '-' || text[7] != '-' || (text[10] != 'T' && text[10] != 't') || text[13] != ':' || text[16] != ':') {
    return null;
  }
  int? digitAt(int offset, int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      final code = text.codeUnitAt(offset + i);
      if (code < 0x30 || code > 0x39) return null;
      value = value * 10 + (code - 0x30);
    }
    return value;
  }

  final year = digitAt(0, 4);
  final month = digitAt(5, 2);
  final day = digitAt(8, 2);
  final hour = digitAt(11, 2);
  final minute = digitAt(14, 2);
  final second = digitAt(17, 2);
  if (year == null || month == null || day == null || hour == null || minute == null || second == null) {
    return null;
  }
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) {
    return null;
  }
  var rest = text.substring(stampLength);
  if (rest.startsWith('.')) {
    final end = rest.indexOf(RegExp(r'[^0-9]'), 1);
    if (end == 1) return null;
    rest = end == -1 ? '' : rest.substring(end);
  }
  // RFC 3339 requires a zone; a bare local time would be ambiguous, so
  // reject it.
  var offsetMinutes = 0;
  var zoned = false;
  if (rest == 'Z' || rest == 'z') {
    zoned = true;
    rest = '';
  } else if (rest.length == 6 && (rest.startsWith('+') || rest.startsWith('-'))) {
    final offsetHour = digitOffset(rest, 1);
    final offsetMinute = digitOffset(rest, 4);
    if (rest[3] != ':' || offsetHour == null || offsetMinute == null) return null;
    if (offsetHour > 23 || offsetMinute > 59) return null;
    offsetMinutes = offsetHour * 60 + offsetMinute;
    if (rest.startsWith('-')) offsetMinutes = -offsetMinutes;
    zoned = true;
    rest = '';
  }
  if (!zoned || rest.isNotEmpty) return null;

  final utc = DateTime.utc(year, month, day, hour, minute, second);
  return utc.subtract(Duration(minutes: offsetMinutes));
}

int? digitOffset(String text, int offset) {
  var value = 0;
  for (var i = 0; i < 2; i++) {
    final code = text.codeUnitAt(offset + i);
    if (code < 0x30 || code > 0x39) return null;
    value = value * 10 + (code - 0x30);
  }
  return value;
}

bool _printable(String value, int limit) {
  if (value.isEmpty || value.length > limit) return false;
  for (final code in value.codeUnits) {
    if (code < 0x20 || code == 0x7F) return false;
  }
  return true;
}

/// Parses `/api/me` keeping only the printable account name and plan; any
/// other field (e-mail, ids) is dropped, and no credit figures are invented.
String parseOllamaAccountLabel(String json) {
  try {
    final root = jsonDecode(json);
    if (root is! Map<String, dynamic>) return '';
    if (!root.containsKey('name') || root['name'] is! String) return '';
    final name = root['name'] as String;
    if (!_printable(name, 128)) return '';
    if (!root.containsKey('plan') || root['plan'] is! String) return name;
    final plan = root['plan'] as String;
    if (!_printable(plan, 64)) return name;
    return '$name (plan $plan)';
  } catch (_) {
    return '';
  }
}

/// Parses the cloud usage response: a 0..1 monthly fraction becomes a
/// percentage; per-model request counts follow. No currency is invented.
List<Metric> parseOllamaCloudUsage(String json) {
  final metrics = <Metric>[];
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama usage returned malformed JSON', transient: true),
    );
  }
  if (root is! Map<String, dynamic>) {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama usage schema: root must be an object', transient: true),
    );
  }
  if (!root.containsKey('limits') || root['limits'] is! Map<String, dynamic>) {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama usage schema: limits must be an object', transient: true),
    );
  }
  final limits = root['limits'] as Map<String, dynamic>;
  if (!limits.containsKey('monthly') || limits['monthly'] is! Map<String, dynamic>) {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama usage schema: monthly limits must be an object', transient: true),
    );
  }
  final monthly = limits['monthly'] as Map<String, dynamic>;
  if (!monthly.containsKey('usage') || monthly['usage'] is! num) {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama usage schema: monthly usage must be a number', transient: true),
    );
  }
  final fraction = (monthly['usage'] as num).toDouble();
  if (!fraction.isFinite || fraction < 0 || fraction > 1) {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama usage schema: monthly usage is outside 0..1', transient: true),
    );
  }
  final usedPercent = (fraction * 100).toStringAsFixed(1);
  metrics.add(Metric(
    kind: MetricKind.usedPercent,
    value: usedPercent,
    unit: MetricUnit.percent,
    scope: MetricScope.billingPeriod,
    provenance: Provenance.providerReported,
    availability: Availability.available,
    label: 'Creditos mensuales usados',
  ));
  metrics.add(Metric(
    kind: MetricKind.remainingPercent,
    value: subtractDecimals('100.0', usedPercent),
    unit: MetricUnit.percent,
    scope: MetricScope.billingPeriod,
    provenance: Provenance.derived,
    availability: Availability.available,
    label: 'Creditos mensuales restantes',
  ));

  final models = monthly['models'];
  if (models != null) {
    if (models is! List) {
      throw ProviderException(
        ProviderError('refresh-failed', 'Ollama usage schema: monthly models must be an array', transient: true),
      );
    }
    for (final entry in models) {
      if (entry is! Map<String, dynamic>) {
        throw ProviderException(
          ProviderError('refresh-failed', 'Ollama usage schema: model must be an object', transient: true),
        );
      }
      if (!entry.containsKey('name') || entry['name'] is! String) {
        throw ProviderException(
          ProviderError('refresh-failed', 'Ollama usage schema: model name missing', transient: true),
        );
      }
      final name = entry['name'] as String;
      if (name.isEmpty || name.length > 256) {
        throw ProviderException(
          ProviderError('refresh-failed', 'Ollama usage schema: invalid model name', transient: true),
        );
      }
      if (!entry.containsKey('request_count') || entry['request_count'] is! int) {
        throw ProviderException(
          ProviderError('refresh-failed', 'Ollama usage schema: request_count must be an integer', transient: true),
        );
      }
      final requests = entry['request_count'] as int;
      if (requests < 0) {
        throw ProviderException(
          ProviderError('refresh-failed', 'Ollama usage schema: negative request count', transient: true),
        );
      }
      metrics.add(Metric(
        kind: MetricKind.requests,
        value: requests.toString(),
        unit: MetricUnit.requests,
        scope: MetricScope.billingPeriod,
        provenance: Provenance.providerReported,
        availability: Availability.available,
        label: name,
      ));
    }
  }
  return metrics;
}

/// Parses `/api/ps` into the loaded-model count, per-model memory metrics and
/// unload times.
ProviderSnapshot parseOllamaStatus(ProviderConfig config, String json, DateTime observedAt) {
  final snapshot = baseSnapshot(config, observedAt);
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama returned malformed JSON', transient: true),
    );
  }
  if (root is! Map<String, dynamic>) {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama schema: root must be an object', transient: true),
    );
  }
  if (root.containsKey('models') && root['models'] is! List) {
    throw ProviderException(
      ProviderError('refresh-failed', 'Ollama schema: models must be an array', transient: true),
    );
  }

  var loaded = 0;
  snapshot.metrics.add(Metric(
    kind: MetricKind.loadedModels,
    value: '0',
    unit: MetricUnit.count,
    scope: MetricScope.currentObservation,
    provenance: Provenance.providerReported,
    availability: Availability.available,
    label: 'Modelos cargados',
  ));
  final models = root.containsKey('models') ? root['models'] as List<Object?> : const <Object?>[];
  for (final entry in models) {
    if (entry is! Map<String, dynamic>) {
      throw ProviderException(
        ProviderError('refresh-failed', 'Ollama schema: model must be an object', transient: true),
      );
    }
    if (!entry.containsKey('name') || entry['name'] is! String) {
      throw ProviderException(
        ProviderError('refresh-failed', 'Ollama schema: model name missing', transient: true),
      );
    }
    final name = entry['name'] as String;
    if (name.isEmpty || name.length > 256) {
      throw ProviderException(
        ProviderError('refresh-failed', 'Ollama schema: invalid model name', transient: true),
      );
    }
    loaded++;

    final memory = Metric(
      kind: MetricKind.resourceMemory,
      value: '',
      unit: MetricUnit.bytes,
      scope: MetricScope.currentObservation,
      provenance: Provenance.providerReported,
      availability: Availability.unsupported,
      label: name,
    );
    final sizeVram = entry['size_vram'];
    if (sizeVram != null) {
      final value = numberText(sizeVram);
      if ((double.tryParse(value) ?? 0) < 0) {
        throw ProviderException(
          ProviderError('refresh-failed', 'Ollama schema: negative memory value', transient: true),
        );
      }
      memory.value = value;
      memory.availability = Availability.available;
    }
    final expiresAt = entry['expires_at'];
    if (expiresAt != null) {
      if (expiresAt is! String) {
        throw ProviderException(
          ProviderError('refresh-failed', 'Ollama schema: expires_at must be a string', transient: true),
        );
      }
      final unload = parseOllamaUnloadTime(expiresAt);
      if (unload == null) {
        throw ProviderException(
          ProviderError('refresh-failed', 'Ollama schema: invalid unload timestamp', transient: true),
        );
      }
      if (unload.isAfter(observedAt)) memory.resetsAt = unload;
    }
    snapshot.metrics.add(memory);
  }
  snapshot.metrics.first.value = loaded.toString();
  return snapshot;
}

class OllamaProvider extends UsageProvider {
  OllamaProvider(this._config, this._http, this._secrets, this._clock);

  final ProviderConfig _config;
  final HttpTransport _http;
  final SecretStore _secrets;
  final Clock _clock;
  @override
  ProviderConfig get config => _config;

  @override
  void cancel() {}

  @override
  ProviderCapabilities capabilities() {
    final cloud = _config.encryptedCloudKey.isNotEmpty;
    return ProviderCapabilities(
      usage: cloud,
      remaining: cloud,
      detail: cloud
          ? 'Modelos cargados, plan y creditos mensuales; sin recuento de tokens'
          : 'Modelos cargados y plan; anada una API key de ollama.com para los creditos',
    );
  }

  @override
  Future<ConnectionTestResult> testConnection() async {
    try {
      final snapshot = await refresh();
      return ConnectionTestResult(
        success: snapshot.health == Health.healthy,
        capabilities: capabilities(),
        message: 'Ollama /api/ps disponible',
      );
    } on ProviderException catch (error) {
      return ConnectionTestResult(success: false, capabilities: capabilities(), message: error.error.message);
    } catch (error) {
      return ConnectionTestResult(success: false, capabilities: capabilities(), message: error.toString());
    }
  }

  @override
  Future<ProviderSnapshot> refresh() async {
    if (_config.baseUrl.isEmpty) {
      throw ProviderException(ProviderError('refresh-failed', 'Ollama base URL is required', transient: true));
    }
    if (!isSafeEndpointUrl(_config.baseUrl, _config.allowLoopbackHttp)) {
      throw ProviderException(
        ProviderError(
          'unsafe-url',
          'Ollama endpoint must use HTTPS or enabled loopback HTTP',
          transient: false,
        ),
      );
    }
    final request = HttpRequest(
      url: joinUrl(_config.baseUrl, '/api/ps'),
      headers: const {'Accept': 'application/json'},
      allowLoopbackHttp: _config.allowLoopbackHttp,
    );
    final key = await apiKey(_config, _secrets);
    if (key.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $key';
    }
    final response = await _http.send(request);
    requireHttpSuccess(response);
    final snapshot = parseOllamaStatus(_config, response.body, _clock.now());
    snapshot.accountLabel = await _accountLabel(key);
    await _addCloudUsage(snapshot);
    return snapshot;
  }

  /// The credits live on ollama.com, not on the configured server, so they
  /// use their own credential and never the local endpoint's one. A failure
  /// here degrades the snapshot to partial rather than discarding the
  /// loaded-model observation that did succeed.
  Future<void> _addCloudUsage(ProviderSnapshot snapshot) async {
    if (_config.encryptedCloudKey.isEmpty) return;
    try {
      final cloudKey = await _secrets.unprotect(_config.encryptedCloudKey);
      final request = HttpRequest(
        url: ollamaCloudUsageUrl,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $cloudKey',
        },
      );
      final response = await _http.send(request);
      requireHttpSuccess(response);
      snapshot.metrics.addAll(parseOllamaCloudUsage(response.body));
    } on ProviderException catch (error) {
      snapshot.health = Health.partial;
      snapshot.error = error.error;
    } catch (error) {
      snapshot.health = Health.partial;
      snapshot.error = ProviderError('cloud-usage-failed', error.toString(), transient: true);
    }
  }

  /// Supplementary: `/api/me` only labels the snapshot with the signed-in
  /// account, so a server without one must not turn a good observation into
  /// an error.
  Future<String> _accountLabel(String key) async {
    try {
      final request = HttpRequest(
        method: 'POST',
        url: joinUrl(_config.baseUrl, '/api/me'),
        headers: {
          'Accept': 'application/json',
          if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        },
        allowLoopbackHttp: _config.allowLoopbackHttp,
      );
      final response = await _http.send(request);
      if (response.status < 200 || response.status >= 300) return '';
      return parseOllamaAccountLabel(response.body);
    } catch (_) {
      return '';
    }
  }
}