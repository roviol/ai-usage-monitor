/// DeepSeek adapter: queries `GET /user/balance` with a Bearer credential and
/// parses `is_available`/`balance_infos` into per-currency balance metrics,
/// plus an unsupported token metric and an optional derived spend metric.
library;

import 'dart:convert';

import '../config/settings.dart';
import '../domain/decimal.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import 'base.dart';
import 'provider.dart';
import 'provider_exception.dart';

/// Parses the balance endpoint response with the reference's rules.
ProviderSnapshot parseDeepSeekBalance(ProviderConfig config, String json, DateTime observedAt) {
  final snapshot = baseSnapshot(config, observedAt);
  final Object root;
  try {
    root = jsonDecode(json) as Object;
  } on FormatException {
    throw ProviderException(
      ProviderError('refresh-failed', 'DeepSeek returned malformed JSON', transient: true),
    );
  }
  if (root is! Map<String, dynamic>) {
    throw ProviderException(
      ProviderError('refresh-failed', 'DeepSeek schema: is_available missing', transient: true),
    );
  }
  if (!root.containsKey('is_available') || root['is_available'] is! bool) {
    throw ProviderException(
      ProviderError('refresh-failed', 'DeepSeek schema: is_available missing', transient: true),
    );
  }
  if (!root.containsKey('balance_infos') || root['balance_infos'] is! List) {
    throw ProviderException(
      ProviderError('refresh-failed', 'DeepSeek schema: balance_infos missing', transient: true),
    );
  }
  final balances = root['balance_infos'] as List<Object?>;
  for (final entry in balances) {
    if (entry is! Map<String, dynamic>) {
      throw ProviderException(
        ProviderError('refresh-failed', 'DeepSeek schema: balance_infos entries must be objects', transient: true),
      );
    }
    final currency = entry['currency'];
    if (currency is! String) {
      throw ProviderException(
        ProviderError('refresh-failed', 'DeepSeek schema: currency must be a string', transient: true),
      );
    }
    final totalBalance = entry['total_balance'];
    final value = numberText(totalBalance);
    final unit = switch (currency) {
      'USD' => MetricUnit.usd,
      'CNY' => MetricUnit.cny,
      _ => MetricUnit.unknown,
    };
    snapshot.metrics.add(Metric(
      kind: MetricKind.balance,
      value: value,
      unit: unit,
      scope: MetricScope.currentBalance,
      provenance: Provenance.providerReported,
      availability: Availability.available,
      label: 'Saldo $currency',
    ));
    final budget = config.budget;
    if (budget != null && unit != MetricUnit.unknown) {
      snapshot.metrics.add(Metric(
        kind: MetricKind.spent,
        value: subtractDecimals(budget, value),
        unit: unit,
        scope: MetricScope.billingPeriod,
        provenance: Provenance.derived,
        availability: Availability.available,
        label: 'Consumido derivado $currency',
      ));
    }
  }
  if (root['is_available'] as bool == false) {
    snapshot.health = Health.partial;
    snapshot.error = ProviderError(
      'balance-unavailable',
      'DeepSeek reporta saldo no disponible',
      transient: false,
    );
  }
  snapshot.metrics
      .add(unsupported(MetricKind.totalTokens, MetricUnit.tokens, MetricScope.billingPeriod, 'Tokens usados'));
  return snapshot;
}

class DeepSeekProvider extends UsageProvider {
  DeepSeekProvider(this._config, this._http, this._secrets, this._clock);

  final ProviderConfig _config;
  final HttpTransport _http;
  final SecretStore _secrets;
  final Clock _clock;
  @override
  ProviderConfig get config => _config;

  @override
  void cancel() {}

  @override
  ProviderCapabilities capabilities() =>
      const ProviderCapabilities(balance: true, detail: 'DeepSeek /user/balance');

  @override
  Future<ConnectionTestResult> testConnection() async {
    try {
      final snapshot = await refresh();
      return ConnectionTestResult(
        success: snapshot.health != Health.error,
        capabilities: capabilities(),
        message: 'Saldo DeepSeek disponible',
      );
    } on ProviderException catch (error) {
      return ConnectionTestResult(success: false, capabilities: capabilities(), message: error.error.message);
    } catch (error) {
      return ConnectionTestResult(success: false, capabilities: capabilities(), message: error.toString());
    }
  }

  @override
  Future<ProviderSnapshot> refresh() async {
    final key = await apiKey(_config, _secrets);
    if (key.isEmpty) {
      throw ProviderException(ProviderError('missing-key', 'DeepSeek API key is required', transient: false));
    }
    final base = _config.baseUrl.isEmpty ? 'https://api.deepseek.com' : _config.baseUrl;
    final request = HttpRequest(
      url: joinUrl(base, _config.balancePath.isEmpty ? '/user/balance' : _config.balancePath),
      headers: {
        'Authorization': 'Bearer $key',
        'Accept': 'application/json',
      },
      allowLoopbackHttp: _config.allowLoopbackHttp,
    );
    final response = await _http.send(request);
    requireHttpSuccess(response);
    return parseDeepSeekBalance(_config, response.body, _clock.now());
  }
}