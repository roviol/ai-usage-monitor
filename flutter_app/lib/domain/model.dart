/// Domain enums with the same wire strings as the C++ reference.
///
/// Wire strings are the values serialized into settings.json/cache.json and
/// must never change; they are the cross-application contract.
library;

/// Provider kinds, in the reference's declaration order.
enum ProviderKind {
  codex('codex'),
  claudeSubscription('claude-subscription'),
  deepSeek('deepseek'),
  openAiCompatible('openai-compatible'),
  ollama('ollama');

  const ProviderKind(this.wire);

  /// Wire string used in persisted files.
  final String wire;

  /// Parses a wire string; unknown values throw like the reference.
  static ProviderKind parse(String text) {
    for (final value in ProviderKind.values) {
      if (value.wire == text) return value;
      if (text == 'claude-api' && value == ProviderKind.claudeSubscription) {
        return ProviderKind.claudeSubscription;
      }
    }
    throw ArgumentError.value(text, 'kind', 'unknown provider kind');
  }
}

enum MetricKind {
  usedPercent('used-percent'),
  remainingPercent('remaining-percent'),
  inputTokens('input-tokens'),
  outputTokens('output-tokens'),
  totalTokens('total-tokens'),
  balance('balance'),
  spent('spent'),
  requests('requests'),
  loadedModels('loaded-models'),
  resourceMemory('resource-memory');

  const MetricKind(this.wire);

  final String wire;

  static MetricKind parse(String text) {
    for (final value in MetricKind.values) {
      if (value.wire == text) return value;
    }
    throw ArgumentError.value(text, 'kind', 'unknown metric kind');
  }
}

enum MetricUnit {
  percent('percent'),
  tokens('tokens'),
  requests('requests'),
  usd('USD'),
  cny('CNY'),
  seconds('seconds'),
  count('count'),
  bytes('bytes'),
  unknown('unknown');

  const MetricUnit(this.wire);

  final String wire;

  static MetricUnit parse(String text) {
    for (final value in MetricUnit.values) {
      if (value.wire == text) return value;
    }
    throw ArgumentError.value(text, 'unit', 'unknown metric unit');
  }
}

enum MetricScope {
  rollingWindow('rolling-window'),
  day('day'),
  billingPeriod('billing-period'),
  lifetime('lifetime'),
  currentBalance('current-balance'),
  currentObservation('current-observation');

  const MetricScope(this.wire);

  final String wire;

  static MetricScope parse(String text) {
    for (final value in MetricScope.values) {
      if (value.wire == text) return value;
    }
    throw ArgumentError.value(text, 'scope', 'unknown metric scope');
  }
}

enum Provenance {
  providerReported('provider-reported'),
  cliBridge('cli-bridge'),
  locallyObserved('locally-observed'),
  derived('derived');

  const Provenance(this.wire);

  final String wire;

  static Provenance parse(String text) {
    for (final value in Provenance.values) {
      if (value.wire == text) return value;
    }
    throw ArgumentError.value(text, 'provenance', 'unknown metric provenance');
  }
}

enum Availability {
  available('available'),
  unsupported('unsupported'),
  unauthorized('unauthorized'),
  unavailable('unavailable'),
  disabled('disabled');

  const Availability(this.wire);

  final String wire;

  static Availability parse(String text) {
    for (final value in Availability.values) {
      if (value.wire == text) return value;
    }
    throw ArgumentError.value(text, 'availability', 'unknown metric availability');
  }
}

enum Freshness {
  fresh('fresh'),
  stale('stale'),
  noData('no-data');

  const Freshness(this.wire);

  final String wire;

  static Freshness parse(String text) {
    for (final value in Freshness.values) {
      if (value.wire == text) return value;
    }
    throw ArgumentError.value(text, 'freshness', 'unknown snapshot freshness');
  }
}

enum Health {
  healthy('healthy'),
  partial('partial'),
  error('error'),
  disabled('disabled');

  const Health(this.wire);

  final String wire;

  static Health parse(String text) {
    for (final value in Health.values) {
      if (value.wire == text) return value;
    }
    throw ArgumentError.value(text, 'health', 'unknown snapshot health');
  }
}

/// Wire string of an enum value, or `unknown` outside the known set — matching
/// the reference's `EnumString` fallback.
String enumString(Enum? value) {
  if (value == null) return 'unknown';
  final wire = switch (value) {
    ProviderKind v => v.wire,
    MetricKind v => v.wire,
    MetricUnit v => v.wire,
    MetricScope v => v.wire,
    Provenance v => v.wire,
    Availability v => v.wire,
    Freshness v => v.wire,
    Health v => v.wire,
    _ => null,
  };
  return wire ?? 'unknown';
}

/// One measured quantity attached to a snapshot.
class Metric {
  Metric({
    this.kind = MetricKind.totalTokens,
    this.value = '',
    this.unit = MetricUnit.unknown,
    this.scope = MetricScope.lifetime,
    this.provenance = Provenance.providerReported,
    this.availability = Availability.available,
    this.resetsAt,
    this.window,
    this.label = '',
  });

  MetricKind kind;
  String value;
  MetricUnit unit;
  MetricScope scope;
  Provenance provenance;
  Availability availability;
  DateTime? resetsAt;
  Duration? window;
  String label;

  Metric copy() => Metric(
        kind: kind,
        value: value,
        unit: unit,
        scope: scope,
        provenance: provenance,
        availability: availability,
        resetsAt: resetsAt,
        window: window,
        label: label,
      );

  @override
  bool operator ==(Object other) =>
      other is Metric &&
      other.kind == kind &&
      other.value == value &&
      other.unit == unit &&
      other.scope == scope &&
      other.provenance == provenance &&
      other.availability == availability &&
      other.resetsAt == resetsAt &&
      other.window == window &&
      other.label == label;

  @override
  int get hashCode => Object.hash(
        kind, value, unit, scope, provenance, availability, resetsAt, window, label,
      );

  @override
  String toString() =>
      'Metric(${kind.wire}, $value, ${unit.wire}, ${scope.wire}, '
      '${provenance.wire}, ${availability.wire}, $resetsAt, $window, $label)';
}

/// Provider-level error attached to a snapshot.
class ProviderError {
  ProviderError(this.code, this.message, {this.transient = false, this.retryAfter});

  String code;
  String message;
  bool transient;
  Duration? retryAfter;

  ProviderError copy() => ProviderError(code, message, transient: transient, retryAfter: retryAfter);

  @override
  bool operator ==(Object other) =>
      other is ProviderError &&
      other.code == code &&
      other.message == message &&
      other.transient == transient &&
      other.retryAfter == retryAfter;

  @override
  int get hashCode => Object.hash(code, message, transient, retryAfter);

  @override
  String toString() => 'ProviderError($code, $message, $transient, $retryAfter)';
}

/// Normalized provider state published by a refresh.
class ProviderSnapshot {
  ProviderSnapshot({
    this.providerId = '',
    this.displayName = '',
    this.kind = ProviderKind.openAiCompatible,
    DateTime? observedAt,
    this.freshness = Freshness.noData,
    this.health = Health.disabled,
    List<Metric>? metrics,
    this.error,
    this.accountLabel = '',
  })  : observedAt = observedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        metrics = metrics ?? <Metric>[];

  String providerId;
  String displayName;
  ProviderKind kind;
  DateTime observedAt;
  Freshness freshness;
  Health health;
  List<Metric> metrics;
  ProviderError? error;
  String accountLabel;

  ProviderSnapshot copy() => ProviderSnapshot(
        providerId: providerId,
        displayName: displayName,
        kind: kind,
        observedAt: observedAt,
        freshness: freshness,
        health: health,
        metrics: [for (final metric in metrics) metric.copy()],
        error: error?.copy(),
        accountLabel: accountLabel,
      );

  @override
  String toString() =>
      'ProviderSnapshot($providerId, $displayName, ${kind.wire}, $observedAt, '
      '${freshness.wire}, ${health.wire}, $metrics, $error, $accountLabel)';
}

/// Result of snapshot validation.
class ValidationResult {
  ValidationResult({this.valid = true, List<String>? errors}) : errors = errors ?? <String>[];

  bool valid;
  final List<String> errors;
}

/// Result of metric aggregation.
class MetricAggregationResult {
  MetricAggregationResult({this.valid = false, this.metric, this.error = ''});

  bool valid;
  Metric? metric;
  String error;
}