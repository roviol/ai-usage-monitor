/// Presentation formatting ported from `tooltip.cpp` and `overlay.cpp`:
/// metric formatting, tooltip composition, countdowns and overlay projection.
library;

import '../domain/model.dart';
import '../domain/overlay_types.dart';
import '../domain/validate.dart';

/// Formats a metric the way the reference's `FormatMetric` does.
String formatMetric(Metric metric) {
  if (metric.availability != Availability.available) return 'N/D';
  if (metric.kind == MetricKind.loadedModels) {
    final count = (double.tryParse(metric.value) ?? 0).round();
    return '${metric.value}${count == 1 ? ' modelo' : ' modelos'}';
  }
  if (metric.kind == MetricKind.balance || metric.kind == MetricKind.spent) {
    return '${metric.value} ${metric.unit.wire}';
  }
  if (metric.unit == MetricUnit.percent) {
    return '${metric.value}%';
  }
  return '${metric.value} ${metric.unit.wire}';
}

int _priority(ProviderSnapshot snapshot) {
  if (snapshot.health == Health.error) return 0;
  if (snapshot.health == Health.partial || snapshot.freshness == Freshness.stale) return 1;
  if (snapshot.health == Health.healthy) return 2;
  return 3;
}

/// Observation age text used by cards and tooltips.
String ageText(ProviderSnapshot snapshot, DateTime now) {
  if (snapshot.observedAt.millisecondsSinceEpoch == 0) return 'sin datos';
  final elapsed = now.isAfter(snapshot.observedAt) ? now.difference(snapshot.observedAt) : Duration.zero;
  final minutes = elapsed.inMinutes;
  if (minutes < 1) return 'ahora';
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 48) return '${hours}h';
  return '${hours ~/ 24}d';
}

/// Default tooltip length cap used by the tray.
const int maxTooltipCharacters = 127;

/// Composes the tray tooltip with the reference's priority ordering, metric
/// selection, stale suffix and length cap.
String composeTooltip(List<ProviderSnapshot> snapshots, DateTime now, [int maxCharacters = maxTooltipCharacters]) {
  if (maxCharacters == 0) return '';
  final aggregate = aggregateHealth(snapshots);
  final ordered = [...snapshots]..sort((left, right) {
      final leftPriority = _priority(left);
      final rightPriority = _priority(right);
      if (leftPriority != rightPriority) return leftPriority - rightPriority;
      if (left.displayName != right.displayName) return left.displayName.compareTo(right.displayName);
      return left.providerId.compareTo(right.providerId);
    });
  final parts = <String>[];
  parts.add('IA: ${aggregate.wire}');
  for (final snapshot in ordered) {
    if (snapshot.health == Health.disabled) continue;
    var part = '${snapshot.displayName}: ';
    final error = snapshot.error;
    if (error != null) {
      part += error.code;
    } else {
      final metric = snapshot.metrics.cast<Metric?>().firstWhere(
            (candidate) =>
                candidate!.availability == Availability.available &&
                (candidate.kind == MetricKind.usedPercent ||
                    candidate.kind == MetricKind.balance ||
                    candidate.kind == MetricKind.totalTokens ||
                    candidate.kind == MetricKind.loadedModels),
            orElse: () => null,
          );
      part += metric == null ? 'sin datos' : formatMetric(metric);
    }
    part += ' ${ageText(snapshot, now)}';
    if (snapshot.freshness == Freshness.stale) part += ' stale';
    parts.add(part);
  }
  var result = '';
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    final candidate = result.isEmpty ? part : '$result | $part';
    if (candidate.length > maxCharacters) {
      if (index == 1 && result.length + 3 < maxCharacters) {
        result = '$result | ${part.substring(0, maxCharacters - result.length - 3)}';
      }
      break;
    }
    result = candidate;
  }
  if (result.isEmpty) result = 'AI Usage Monitor';
  if (result.length > maxCharacters) result = result.substring(0, maxCharacters);
  return result;
}

double? _parsePercent(Metric metric) {
  if (metric.kind != MetricKind.usedPercent || metric.availability != Availability.available) {
    return null;
  }
  final value = double.tryParse(metric.value);
  if (value == null || !value.isFinite) return null;
  return value.clamp(0.0, 100.0);
}

/// Row status text with the reference's precedence and wording.
String rowStatus(ProviderSnapshot snapshot) {
  final error = snapshot.error;
  if (error != null && error.code == 'refreshing') return 'actualizando';
  if (snapshot.health == Health.error) {
    return snapshot.freshness == Freshness.stale ? 'error · anterior' : 'error';
  }
  if (snapshot.freshness == Freshness.stale) return 'anterior';
  if (snapshot.health == Health.partial) return 'parcial';
  if (snapshot.health == Health.disabled) return 'desactivado';
  if (snapshot.freshness == Freshness.noData) return 'sin datos';
  return '';
}

OverlayRow _makeStatusRow(ProviderSnapshot snapshot) {
  var status = rowStatus(snapshot);
  if (status.isEmpty) status = 'sin datos';
  return OverlayRow(
    providerId: snapshot.providerId,
    providerName: snapshot.displayName,
    label: 'Estado',
    value: status,
    usedPercent: null,
    resetsAt: null,
    resetText: '',
    statusText: status,
  );
}

/// Formats the reset countdown, mirroring `FormatResetCountdown`.
String formatResetCountdown(DateTime? resetsAt, DateTime now) {
  if (resetsAt == null) return '';
  final remaining = resetsAt.difference(now).inSeconds;
  if (remaining <= 0) return 'reiniciando';
  if (remaining < 60) return 'reinicia en <1m';
  final minutes = (remaining + 59) ~/ 60;
  if (minutes < 60) return 'reinicia en ${minutes}m';
  final hours = minutes ~/ 60;
  final minutePart = minutes % 60;
  if (hours < 24) {
    return 'reinicia en ${hours}h${minutePart == 0 ? '' : ' ${minutePart}m'}';
  }
  final days = hours ~/ 24;
  final hourPart = hours % 24;
  return 'reinicia en ${days}d${hourPart == 0 ? '' : ' ${hourPart}h'}';
}

/// Formats the unload countdown for resource-memory rows.
String formatUnloadCountdown(DateTime? resetsAt, DateTime now) {
  if (resetsAt == null) return '';
  final remaining = resetsAt.difference(now).inSeconds;
  if (remaining <= 0) return 'descargando';
  if (remaining < 60) return 'descarga en <1m';
  final minutes = (remaining + 59) ~/ 60;
  if (minutes < 60) return 'descarga en ${minutes}m';
  final hours = minutes ~/ 60;
  final minutePart = minutes % 60;
  if (hours < 24) {
    return 'descarga en ${hours}h${minutePart == 0 ? '' : ' ${minutePart}m'}';
  }
  final days = hours ~/ 60 ~/ 24;
  final hourPart = hours % 24;
  return 'descarga en ${days}d${hourPart == 0 ? '' : ' ${hourPart}h'}';
}

/// Next repaint moment: the earliest of the next minute boundary and the
/// earliest future reset, mirroring `NextOverlayCountdownUpdate`.
DateTime? nextOverlayCountdownUpdate(List<OverlayRow> rows, DateTime now) {
  DateTime? earliest;
  var hasFutureReset = false;
  for (final row in rows) {
    final reset = row.resetsAt;
    if (reset == null || !reset.isAfter(now)) continue;
    hasFutureReset = true;
    if (earliest == null || reset.isBefore(earliest)) earliest = reset;
  }
  if (!hasFutureReset) return null;
  final secondsSinceEpoch = now.millisecondsSinceEpoch ~/ 1000;
  final nextMinute = DateTime.fromMillisecondsSinceEpoch(
    ((secondsSinceEpoch ~/ 60 + 1) * 60) * 1000,
    isUtc: now.isUtc,
  );
  return nextMinute.isBefore(earliest!) ? nextMinute : earliest;
}

/// Visible row capacity given 40% of the work area, mirroring
/// `OverlayRowCapacity`.
int overlayRowCapacity(int workAreaHeight, int fixedHeight, int rowHeight) {
  if (workAreaHeight <= 0 || rowHeight <= 0) return 0;
  final maximum = (workAreaHeight * 0.4).floor();
  if (maximum <= fixedHeight) return 0;
  return (maximum - fixedHeight) ~/ rowHeight;
}

/// Fixed chrome height of the overlay above its rows.
const int fixedOverlayHeight = 0;

/// Nearest corner snapping, mirroring `NearestOverlayCorner`.
OverlayCorner nearestOverlayCorner(
  int windowX,
  int windowY,
  int windowWidth,
  int windowHeight,
  int workLeft,
  int workTop,
  int workRight,
  int workBottom,
  int margin,
) {
  final left = workLeft + margin;
  final right = workRight - windowWidth - margin;
  final top = workTop + margin;
  final bottom = workBottom - windowHeight - margin;
  final chooseRight = (windowX - right).abs() < (windowX - left).abs();
  final chooseBottom = (windowY - bottom).abs() < (windowY - top).abs();
  return chooseBottom
      ? (chooseRight ? OverlayCorner.bottomRight : OverlayCorner.bottomLeft)
      : (chooseRight ? OverlayCorner.topRight : OverlayCorner.topLeft);
}

/// Whether a window rectangle covers the whole monitor, used by the Windows
/// full-screen suppression.
bool coversOverlayMonitor(
  int windowLeft,
  int windowTop,
  int windowRight,
  int windowBottom,
  int monitorLeft,
  int monitorTop,
  int monitorRight,
  int monitorBottom,
) =>
    windowLeft <= monitorLeft &&
    windowTop <= monitorTop &&
    windowRight >= monitorRight &&
    windowBottom >= monitorBottom;

/// Projects snapshots into overlay rows with the reference's filtering,
/// status precedence and hidden-count rules.
OverlayProjection projectOverlayRows(List<ProviderSnapshot> snapshots, DateTime now, int capacity) {
  final projected = <OverlayRow>[];
  for (final snapshot in snapshots) {
    final status = rowStatus(snapshot);
    final before = projected.length;
    for (final metric in snapshot.metrics) {
      if (metric.kind == MetricKind.remainingPercent || metric.availability != Availability.available) {
        continue;
      }
      final instantaneous = metric.kind == MetricKind.loadedModels || metric.kind == MetricKind.resourceMemory;
      if (!instantaneous &&
          metric.kind != MetricKind.usedPercent &&
          metric.kind != MetricKind.balance &&
          metric.kind != MetricKind.spent) {
        continue;
      }
      final percent = _parsePercent(metric);
      if (metric.kind == MetricKind.usedPercent && percent == null) continue;
      final label = metric.label.isEmpty
          ? (metric.kind == MetricKind.balance ? 'Balance' : 'Uso')
          : metric.label;
      final resetText = metric.kind == MetricKind.resourceMemory
          ? formatUnloadCountdown(metric.resetsAt, now)
          : formatResetCountdown(metric.resetsAt, now);
      projected.add(OverlayRow(
        providerId: snapshot.providerId,
        providerName: snapshot.displayName,
        label: label,
        value: formatMetric(metric),
        usedPercent: percent,
        resetsAt: metric.resetsAt,
        resetText: resetText,
        statusText: status,
      ));
    }
    if (projected.length == before && (snapshot.health != Health.healthy || snapshot.freshness != Freshness.fresh)) {
      projected.add(_makeStatusRow(snapshot));
    }
  }

  if (projected.length <= capacity) {
    return OverlayProjection(rows: projected);
  }
  final visible = capacity == 0 ? 0 : capacity - 1;
  final hiddenCount = projected.length - visible;
  return OverlayProjection(rows: projected.sublist(0, visible), hiddenCount: hiddenCount);
}