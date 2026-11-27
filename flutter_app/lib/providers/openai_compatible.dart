/// OpenAI-compatible adapter: `/models` connection test, route resolution and
/// ordered JSON Pointer mappings emitting the reference metric order, failing
/// the whole refresh when a configured pointer is absent.
library;

import 'dart:convert';

import '../config/settings.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import 'base.dart';
import 'provider.dart';
import 'provider_exception.dart';

const int _maxPointerHops = 64;

/// Resolves a JSON Pointer (RFC 6901) against [document] like
/// `nlohmann::json::contains/at` do, returning null when absent.
Object? resolveJsonPointer(Object? document, String pointer) {
  if (!pointer.startsWith('/')) return null;
  var current = document;
  var hops = 0;
  var index = 0;
  while (index < pointer.length) {
    if (pointer[index] != '/') return null;
    index++;
    var token = '';
    while (index < pointer.length && pointer[index] != '/') {
      token += pointer[index];
      index++;
    }
    token = token.replaceAll('~1', '/').replaceAll('~0', '~');
    if (hops++ >= _maxPointerHops) return null;
    if (current is List<Object?>) {
      final position = int.tryParse(token);
      if (position == null || position < 0 || position >= current.length) return null;
      current = current[position];
    } else if (current is Map<String, dynamic>) {
      if (!current.containsKey(token)) return null;
      current = current[token];
    } else {
      return null;
    }
  }
  return current;
}

/// Parses the usage/balance response into metrics in the reference order.
List<Metric> parseGenericMetrics(ProviderConfig config, String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException {
    throw ProviderException(
      ProviderError('refresh-failed', 'usage endpoint returned malformed JSON', transient: true),
    );
  }
  final metrics = <Metric>[];
  void add(String key, MetricKind kind, MetricUnit unit, MetricScope scope, String label) {
    final pointer = config.jsonPointers[key];
    if (pointer == null || pointer.isEmpty) return;
    final value = resolveJsonPointer(root, pointer);
    if (value == null) {
      throw ProviderException(
        ProviderError('missing-pointer', 'JSON Pointer missing for $key', transient: true),
      );
    }
    metrics.add(Metric(
      kind: kind,
      value: numberText(value),
      unit: unit,
      scope: scope,
      provenance: Provenance.providerReported,
      availability: Availability.available,
      label: label,
    ));
  }

  add('used_percent', MetricKind.usedPercent, MetricUnit.percent, MetricScope.billingPeriod, 'Uso');
  add('remaining_percent', MetricKind.remainingPercent, MetricUnit.percent, MetricScope.billingPeriod, 'Restante');
  add('total_tokens', MetricKind.totalTokens, MetricUnit.tokens, MetricScope.billingPeriod, 'Tokens');
  add('balance_usd', MetricKind.balance, MetricUnit.usd, MetricScope.currentBalance, 'Saldo USD');
  add('balance_cny', MetricKind.balance, MetricUnit.cny, MetricScope.currentBalance, 'Saldo CNY');
  add('spent_usd', MetricKind.spent, MetricUnit.usd, MetricScope.billingPeriod, 'Consumido USD');
  return metrics;
}

class GenericProvider extends UsageProvider {
  GenericProvider(this._config, this._http, this._secrets, this._clock);

  final ProviderConfig _config;
  final HttpTransport _http;
  final SecretStore _secrets;
  final Clock _clock;
  @override
  ProviderConfig get config => _config;

  @override
  void cancel() {}

  @override
  ProviderCapabilities capabilities() => ProviderCapabilities(
        usage: _config.usagePath.isNotEmpty,
        remaining: _config.jsonPointers.containsKey('remaining_percent'),
        balance: _config.balancePath.isNotEmpty,
        tokenActivity: _config.jsonPointers.containsKey('total_tokens'),
        detail: 'Mappings explícitos',
      );

  @override
  Future<ConnectionTestResult> testConnection() async {
    try {
      final key = await apiKey(_config, _secrets);
      final request = HttpRequest(
        url: joinUrl(_config.baseUrl, '/models'),
        headers: {
          if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        },
        allowLoopbackHttp: _config.allowLoopbackHttp,
      );
      final response = await _http.send(request);
      requireHttpSuccess(response);
      return ConnectionTestResult(
        success: true,
        capabilities: capabilities(),
        message: 'Endpoint compatible accesible',
      );
    } on ProviderException catch (error) {
      return ConnectionTestResult(success: false, capabilities: capabilities(), message: error.error.message);
    } catch (error) {
      return ConnectionTestResult(success: false, capabilities: capabilities(), message: error.toString());
    }
  }

  @override
  Future<ProviderSnapshot> refresh() async {
    final snapshot = baseSnapshot(_config, _clock.now());
    final key = await apiKey(_config, _secrets);
    final path = _config.usagePath.isNotEmpty ? _config.usagePath : _config.balancePath;
    if (path.isEmpty) {
      final test = await testConnection();
      if (!test.success) {
        throw ProviderException(ProviderError('refresh-failed', test.message, transient: true));
      }
      snapshot.health = Health.partial;
      snapshot.metrics.add(unsupported(MetricKind.balance, MetricUnit.unknown, MetricScope.currentBalance, 'Saldo'));
      snapshot.metrics
          .add(unsupported(MetricKind.totalTokens, MetricUnit.tokens, MetricScope.billingPeriod, 'Uso'));
      return snapshot;
    }
    final request = HttpRequest(
      url: joinUrl(_config.baseUrl, path),
      headers: {
        if (key.isNotEmpty) 'Authorization': 'Bearer $key',
      },
      allowLoopbackHttp: _config.allowLoopbackHttp,
    );
    final response = await _http.send(request);
    requireHttpSuccess(response);
    snapshot.metrics = parseGenericMetrics(_config, response.body);
    snapshot.health = snapshot.metrics.isEmpty ? Health.partial : Health.healthy;
    return snapshot;
  }
}