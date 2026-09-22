import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/domain/domain.dart';

void main() {
  group('isDecimal', () {
    test('accepts reference-shaped values', () {
      expect(isDecimal('0'), isTrue);
      expect(isDecimal('42'), isTrue);
      expect(isDecimal('42.5'), isTrue);
      expect(isDecimal('0.5'), isTrue);
      expect(isDecimal('-12.25'), isTrue);
      expect(isDecimal('100'), isTrue);
    });

    test('rejects malformed values', () {
      expect(isDecimal(''), isFalse);
      expect(isDecimal('042'), isFalse);
      expect(isDecimal('42.'), isFalse);
      expect(isDecimal('.5'), isFalse);
      expect(isDecimal('1e3'), isFalse);
      expect(isDecimal('abc'), isFalse);
      expect(isDecimal('-'), isFalse);
      expect(isDecimal('1,5'), isFalse);
      expect(isDecimal('nan'), isFalse);
      expect(isDecimal('Infinity'), isFalse);
    });

    test('rejects values that are not finite', () {
      expect(isDecimal('9' * 400), isFalse);
    });
  });

  group('addDecimals', () {
    test('normalizes 42.50 to 42.5', () {
      expect(addDecimals('40', '2.50'), '42.5');
    });

    test('reference edge case 100.0 - 38.2 = 61.8', () {
      expect(subtractDecimals('100.0', '38.2'), '61.8');
    });

    test('normalizes zero without sign', () {
      expect(addDecimals('0.0', '0.00'), '0');
      expect(addDecimals('5', '-5.0'), '0');
      expect(subtractDecimals('38.2', '38.2'), '0');
    });

    test('aligns scales from both operands', () {
      expect(addDecimals('0.1', '0.02'), '0.12');
      expect(addDecimals('1.5', '2.25'), '3.75');
    });

    test('handles negative results', () {
      expect(subtractDecimals('1', '2.5'), '-1.5');
      expect(addDecimals('-1.5', '1'), '-0.5');
    });

    test('carries beyond digit length', () {
      expect(addDecimals('999.999', '0.001'), '1000');
      expect(addDecimals('0.09', '0.01'), '0.1');
    });

    test('rejects invalid input', () {
      expect(() => addDecimals('abc', '1'), throwsArgumentError);
      expect(() => addDecimals('04', '1'), throwsArgumentError);
    });
  });

  group('subtractDecimals', () {
    test('derived remaining with exact strings', () {
      expect(subtractDecimals('100', '25'), '75');
      expect(subtractDecimals('100', '61.7'), '38.3');
      expect(subtractDecimals('100.0', '38.2'), '61.8');
    });

    test('negative right operand adds', () {
      expect(subtractDecimals('5', '-3'), '8');
    });
  });

  group('validateSnapshot', () {
    ProviderSnapshot snapshotWith(Metric metric) =>
        ProviderSnapshot(providerId: 'p', displayName: 'P', metrics: [metric]);

    test('requires providerId and displayName', () {
      final result = validateSnapshot(ProviderSnapshot());
      expect(result.valid, isFalse);
      expect(result.errors, ['providerId is required', 'displayName is required']);
    });

    test('rejects non-decimal available value', () {
      final result = validateSnapshot(
        snapshotWith(Metric(value: 'abc', availability: Availability.available, unit: MetricUnit.tokens)),
      );
      expect(result.errors, contains('available metric contains a non-decimal value'));
    });

    test('rejects percentage outside 0..100', () {
      final result = validateSnapshot(
        snapshotWith(
          Metric(value: '101', unit: MetricUnit.percent, availability: Availability.available),
        ),
      );
      expect(result.errors, contains('percentage is outside 0..100'));
      expect(
        validateSnapshot(
          snapshotWith(
            Metric(value: '-1', unit: MetricUnit.percent, availability: Availability.available),
          ),
        ).errors,
        contains('percentage is outside 0..100'),
      );
    });

    test('rejects negative resource metrics', () {
      final result = validateSnapshot(
        snapshotWith(Metric(value: '-5', unit: MetricUnit.bytes, availability: Availability.available)),
      );
      expect(result.errors, contains('resource metric is negative'));
    });

    test('loaded-model metric requires count units', () {
      final result = validateSnapshot(
        snapshotWith(
          Metric(
            kind: MetricKind.loadedModels,
            value: '1',
            unit: MetricUnit.tokens,
            availability: Availability.available,
          ),
        ),
      );
      expect(result.errors, contains('loaded-model metric requires count units'));
    });

    test('resource-memory metric requires byte units', () {
      final result = validateSnapshot(
        snapshotWith(
          Metric(
            kind: MetricKind.resourceMemory,
            value: '1',
            unit: MetricUnit.count,
            availability: Availability.available,
          ),
        ),
      );
      expect(result.errors, contains('resource-memory metric requires byte units'));
    });

    test('window must be positive', () {
      final result = validateSnapshot(
        snapshotWith(Metric(value: '1', unit: MetricUnit.tokens, window: Duration.zero)),
      );
      expect(result.errors, contains('window must be positive'));
    });

    test('unavailable metrics skip value checks', () {
      final result = validateSnapshot(
        snapshotWith(Metric(value: '', unit: MetricUnit.tokens, availability: Availability.unsupported)),
      );
      expect(result.valid, isTrue);
    });
  });

  group('aggregateMetrics', () {
    test('requires at least one metric', () {
      final result = aggregateMetrics([]);
      expect(result.valid, isFalse);
      expect(result.error, 'at least one metric is required');
    });

    test('only available decimals aggregate', () {
      final result = aggregateMetrics([
        Metric(value: 'x', availability: Availability.available, unit: MetricUnit.tokens),
      ]);
      expect(result.valid, isFalse);
      expect(result.error, 'only available decimal metrics can be aggregated');

      final unavailable = aggregateMetrics([
        Metric(value: '1', availability: Availability.unsupported, unit: MetricUnit.tokens),
      ]);
      expect(unavailable.valid, isFalse);
    });

    test('compatibility checks cover kind, unit, scope, provenance and window', () {
      final base = Metric(value: '1', unit: MetricUnit.tokens);
      final mismatch = Metric(value: '2', unit: MetricUnit.requests);
      final result = aggregateMetrics([base, mismatch]);
      expect(result.valid, isFalse);
      expect(result.error, 'metric kind, unit, scope, provenance and window must match');
    });

    test('sums compatible metrics', () {
      Metric metric(String value) => Metric(
            value: value,
            unit: MetricUnit.tokens,
            resetsAt: DateTime.fromMillisecondsSinceEpoch(1000),
            window: const Duration(minutes: 5),
          );
      final result = aggregateMetrics([metric('1.5'), metric('2.25')]);
      expect(result.valid, isTrue);
      expect(result.metric!.value, '3.75');
    });
  });

  group('aggregateHealth', () {
    ProviderSnapshot withHealth(Health health, {Freshness freshness = Freshness.fresh}) =>
        ProviderSnapshot(providerId: 'p', displayName: 'P', health: health, freshness: freshness);

    test('error dominates', () {
      expect(aggregateHealth([withHealth(Health.healthy), withHealth(Health.error)]), Health.error);
    });

    test('all disabled is disabled', () {
      expect(aggregateHealth([withHealth(Health.disabled), withHealth(Health.disabled)]), Health.disabled);
    });

    test('partial and stale degrade to partial', () {
      expect(aggregateHealth([withHealth(Health.healthy), withHealth(Health.partial)]), Health.partial);
      expect(
        aggregateHealth([withHealth(Health.healthy), withHealth(Health.healthy, freshness: Freshness.stale)]),
        Health.partial,
      );
    });

    test('all healthy is healthy', () {
      expect(aggregateHealth([withHealth(Health.healthy), withHealth(Health.healthy)]), Health.healthy);
    });
  });

  group('enum wire strings', () {
    test('match the reference exactly', () {
      expect(enumString(ProviderKind.codex), 'codex');
      expect(enumString(ProviderKind.claudeSubscription), 'claude-subscription');
      expect(enumString(ProviderKind.deepSeek), 'deepseek');
      expect(enumString(ProviderKind.openAiCompatible), 'openai-compatible');
      expect(enumString(ProviderKind.ollama), 'ollama');
      expect(enumString(MetricKind.usedPercent), 'used-percent');
      expect(enumString(MetricKind.remainingPercent), 'remaining-percent');
      expect(enumString(MetricKind.totalTokens), 'total-tokens');
      expect(enumString(MetricKind.balance), 'balance');
      expect(enumString(MetricKind.spent), 'spent');
      expect(enumString(MetricUnit.usd), 'USD');
      expect(enumString(MetricUnit.cny), 'CNY');
      expect(enumString(MetricScope.rollingWindow), 'rolling-window');
      expect(enumString(MetricScope.currentBalance), 'current-balance');
      expect(enumString(Provenance.derived), 'derived');
      expect(enumString(Provenance.cliBridge), 'cli-bridge');
      expect(enumString(Availability.unsupported), 'unsupported');
      expect(enumString(Freshness.stale), 'stale');
      expect(enumString(Freshness.noData), 'no-data');
      expect(enumString(Health.partial), 'partial');
    });

    test('round-trip parsing', () {
      for (final value in ProviderKind.values) {
        expect(ProviderKind.parse(value.wire), value);
      }
      for (final value in MetricKind.values) {
        expect(MetricKind.parse(value.wire), value);
      }
      expect(ProviderKind.parse('claude-api'), ProviderKind.claudeSubscription);
      expect(() => ProviderKind.parse('other'), throwsArgumentError);
      expect(() => MetricUnit.parse('other'), throwsArgumentError);
    });
  });
}