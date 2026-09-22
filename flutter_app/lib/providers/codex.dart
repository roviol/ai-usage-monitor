/// Codex adapter: runs the app-server with the same five JSONL requests as
/// the reference (3000 ms stdin close delay) and parses account,
/// rate-limit and usage responses.
library;

import 'dart:convert';

import '../config/settings.dart';
import '../domain/decimal.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import '../platform/io_impl.dart' show probeVersion;
import 'base.dart';
import 'provider.dart';
import 'provider_exception.dart';

/// Parses one JSON object per non-empty line with the reference's rules.
ProviderSnapshot parseCodexResponses(ProviderConfig config, String jsonLines, DateTime observedAt) {
  final snapshot = baseSnapshot(config, observedAt);
  var accountSeen = false;
  var limitsSeen = false;
  for (final rawLine in LineSplitter.split(jsonLines)) {
    if (rawLine.isEmpty) continue;
    Object? message;
    try {
      message = jsonDecode(rawLine);
    } on FormatException {
      throw ProviderException(
        ProviderError('refresh-failed', 'Codex app-server returned malformed JSONL', transient: true),
      );
    }
    if (message is! Map<String, dynamic>) continue;
    final id = message['id'];
    if (id is! int) continue;
    if (message.containsKey('error')) {
      snapshot.health = Health.error;
      snapshot.error = ProviderError('codex-protocol', jsonEncode(message['error']), transient: false);
      continue;
    }
    if (!message.containsKey('result')) continue;
    final result = message['result'];
    if (result is! Map<String, dynamic>) continue;
    if (id == 2) {
      accountSeen = true;
      final account = result['account'];
      if (!result.containsKey('account') || account == null) {
        snapshot.health = Health.error;
        snapshot.error = ProviderError(
          'unauthorized',
          'Codex no tiene una cuenta autenticada',
          transient: false,
        );
      } else if (account is Map<String, dynamic>) {
        final email = account['email'];
        if (email is String) snapshot.accountLabel = email;
        if (snapshot.accountLabel.isEmpty && account.containsKey('type')) {
          final type = account['type'];
          snapshot.accountLabel = type is String ? type : '';
        }
      }
    } else if (id == 3) {
      limitsSeen = true;
      final byId = result['rateLimitsByLimitId'];
      if (byId is Map<String, dynamic>) {
        byId.forEach((bucketId, bucket) {
          var label = bucketId == 'codex' ? 'Codex' : bucketId;
          if (bucket is Map<String, dynamic>) {
            final reportedLabel = bucket['limitName'];
            if (reportedLabel is String && reportedLabel.isNotEmpty) label = reportedLabel;
            final primary = bucket['primary'];
            if (primary is Map<String, dynamic>) {
              _addCodexWindow(snapshot.metrics, primary, '$label principal');
            }
            final secondary = bucket['secondary'];
            if (secondary != null && secondary is Map<String, dynamic>) {
              _addCodexWindow(snapshot.metrics, secondary, '$label secundaria');
            }
          }
        });
      } else if (result['rateLimits'] is Map<String, dynamic>) {
        final bucket = result['rateLimits'] as Map<String, dynamic>;
        final primary = bucket['primary'];
        if (primary is Map<String, dynamic>) {
          _addCodexWindow(snapshot.metrics, primary, 'Codex principal');
        }
        final secondary = bucket['secondary'];
        if (secondary != null && secondary is Map<String, dynamic>) {
          _addCodexWindow(snapshot.metrics, secondary, 'Codex secundaria');
        }
      }
    } else if (id == 4 && result['summary'] is Map<String, dynamic>) {
      final summary = result['summary'] as Map<String, dynamic>;
      final lifetime = summary['lifetimeTokens'];
      if (lifetime != null) {
        snapshot.metrics.add(Metric(
          kind: MetricKind.totalTokens,
          value: numberText(lifetime),
          unit: MetricUnit.tokens,
          scope: MetricScope.lifetime,
          provenance: Provenance.providerReported,
          availability: Availability.available,
          label: 'Tokens acumulados',
        ));
      }
    }
  }
  if (!accountSeen) {
    throw ProviderException(
      ProviderError('refresh-failed', 'Codex account response was not received', transient: true),
    );
  }
  if (!limitsSeen && snapshot.health != Health.error) snapshot.health = Health.partial;
  if (snapshot.metrics.isEmpty && snapshot.health == Health.healthy) snapshot.health = Health.partial;
  return snapshot;
}

void _addCodexWindow(List<Metric> metrics, Map<String, dynamic> window, String label) {
  if (!window.containsKey('usedPercent')) return;
  final used = numberText(window['usedPercent']);
  DateTime? reset;
  Duration? duration;
  final resetsAt = window['resetsAt'];
  if (resetsAt is int) {
    reset = DateTime.fromMillisecondsSinceEpoch(resetsAt * 1000, isUtc: true);
  }
  final windowDuration = window['windowDurationMins'];
  if (windowDuration is int) {
    duration = Duration(minutes: windowDuration);
  }
  metrics.add(Metric(
    kind: MetricKind.usedPercent,
    value: used,
    unit: MetricUnit.percent,
    scope: MetricScope.rollingWindow,
    provenance: Provenance.providerReported,
    availability: Availability.available,
    resetsAt: reset,
    window: duration,
    label: '$label usado',
  ));
  metrics.add(Metric(
    kind: MetricKind.remainingPercent,
    value: subtractDecimals('100', used),
    unit: MetricUnit.percent,
    scope: MetricScope.rollingWindow,
    provenance: Provenance.derived,
    availability: Availability.available,
    resetsAt: reset,
    window: duration,
    label: '$label restante',
  ));
}

class CodexProvider extends UsageProvider {
  CodexProvider(this._config, this._process, this._clock);

  final ProviderConfig _config;
  final ProcessRunner _process;
  final Clock _clock;
  bool _cancelled = false;

  @override
  ProviderConfig get config => _config;

  @override
  void cancel() => _cancelled = true;

  @override
  ProviderCapabilities capabilities() =>
      const ProviderCapabilities(usage: true, remaining: true, tokenActivity: true, detail: 'Codex app-server');

  @override
  Future<ConnectionTestResult> testConnection() async {
    final version = await probeVersion(_process, _config.executable);
    return ConnectionTestResult(
      success: version.isNotEmpty,
      capabilities: capabilities(),
      message: version.isEmpty ? 'No se pudo ejecutar Codex' : version,
    );
  }

  @override
  Future<ProviderSnapshot> refresh() async {
    _cancelled = false;
    final requests = '{"method":"initialize","id":1,"params":{"clientInfo":{"name":"ai-usage-monitor",'
        '"title":"AI Usage Monitor","version":"0.1.1"},"capabilities":{}}}\n'
        '{"method":"initialized","params":{}}\n'
        '{"method":"account/read","id":2,"params":{"refreshToken":false}}\n'
        '{"method":"account/rateLimits/read","id":3}\n'
        '{"method":"account/usage/read","id":4}\n';
    final result = await _process.run(ProcessRequest(
      executable: _config.executable,
      arguments: const ['app-server', '--listen', 'stdio://'],
      standardInput: requests,
      timeout: const Duration(milliseconds: 10000),
      cancellationRequested: () => _cancelled,
      standardInputCloseDelay: const Duration(milliseconds: 3000),
    ));
    if (result.timedOut) {
      throw ProviderException(ProviderError('timeout', 'Codex app-server timed out', transient: true));
    }
    if (result.standardOutput.isEmpty) {
      throw ProviderException(ProviderError('refresh-failed', 'Codex app-server returned no JSONL', transient: true));
    }
    return parseCodexResponses(_config, result.standardOutput, _clock.now());
  }
}