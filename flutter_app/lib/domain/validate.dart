/// Snapshot validation and metric/health aggregation, ported from the C++
/// reference `ValidateSnapshot`, `AggregateMetrics` and `AggregateHealth`
/// with the same error order and messages.
library;

import 'decimal.dart';
import 'model.dart';

/// Validates a snapshot with the reference's checks and message order.
ValidationResult validateSnapshot(ProviderSnapshot snapshot) {
  final result = ValidationResult();
  if (snapshot.providerId.isEmpty) {
    result.errors.add('providerId is required');
  }
  if (snapshot.displayName.isEmpty) {
    result.errors.add('displayName is required');
  }
  for (final metric in snapshot.metrics) {
    if (metric.availability == Availability.available && !isDecimal(metric.value)) {
      result.errors.add('available metric contains a non-decimal value');
    }
    if (metric.unit == MetricUnit.percent && metric.availability == Availability.available) {
      final parsed = double.tryParse(metric.value) ?? double.nan;
      if (parsed < 0 || parsed > 100) {
        result.errors.add('percentage is outside 0..100');
      }
    }
    if ((metric.unit == MetricUnit.count || metric.unit == MetricUnit.bytes) &&
        metric.availability == Availability.available &&
        (double.tryParse(metric.value) ?? 0) < 0) {
      result.errors.add('resource metric is negative');
    }
    if (metric.kind == MetricKind.loadedModels && metric.unit != MetricUnit.count) {
      result.errors.add('loaded-model metric requires count units');
    }
    if (metric.kind == MetricKind.resourceMemory && metric.unit != MetricUnit.bytes) {
      result.errors.add('resource-memory metric requires byte units');
    }
    final window = metric.window;
    if (window != null && window.inSeconds <= 0) {
      result.errors.add('window must be positive');
    }
  }
  result.valid = result.errors.isEmpty;
  return result;
}

/// Aggregates compatible metrics by summation with the reference's checks.
MetricAggregationResult aggregateMetrics(List<Metric> metrics) {
  if (metrics.isEmpty) {
    return MetricAggregationResult(error: 'at least one metric is required');
  }
  final total = metrics.first.copy();
  if (total.availability != Availability.available || !isDecimal(total.value)) {
    return MetricAggregationResult(error: 'only available decimal metrics can be aggregated');
  }
  for (var index = 1; index < metrics.length; index++) {
    final metric = metrics[index];
    if (metric.availability != Availability.available || !isDecimal(metric.value)) {
      return MetricAggregationResult(error: 'only available decimal metrics can be aggregated');
    }
    if (metric.kind != total.kind ||
        metric.unit != total.unit ||
        metric.scope != total.scope ||
        metric.provenance != total.provenance ||
        metric.resetsAt != total.resetsAt ||
        metric.window != total.window) {
      return MetricAggregationResult(
        error: 'metric kind, unit, scope, provenance and window must match',
      );
    }
    total.value = addDecimals(total.value, metric.value);
  }
  return MetricAggregationResult(valid: true, metric: total);
}

/// Aggregates snapshot health with the reference's precedence:
/// error > partial-or-stale > healthy > disabled.
Health aggregateHealth(List<ProviderSnapshot> snapshots) {
  var enabled = false;
  var partial = false;
  for (final snapshot in snapshots) {
    if (snapshot.health == Health.error) {
      return Health.error;
    }
    if (snapshot.health != Health.disabled) {
      enabled = true;
    }
    if (snapshot.health == Health.partial || snapshot.freshness == Freshness.stale) {
      partial = true;
    }
  }
  if (!enabled) {
    return Health.disabled;
  }
  return partial ? Health.partial : Health.healthy;
}