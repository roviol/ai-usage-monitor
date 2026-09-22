import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/config/settings.dart';
import 'package:ai_usage_monitor/domain/model.dart';
import 'package:ai_usage_monitor/domain/overlay_types.dart';
import 'package:ai_usage_monitor/presentation/presentation.dart';
import 'package:ai_usage_monitor/ui/overlay_window.dart';
import 'package:ai_usage_monitor/ui/theme.dart';

ProviderSnapshot snapshotWith({
  String id = 'a',
  String name = 'A',
  List<Metric> metrics = const [],
  Health health = Health.healthy,
  Freshness freshness = Freshness.fresh,
  ProviderError? error,
}) {
  final snapshot = ProviderSnapshot(
    providerId: id,
    displayName: name,
    observedAt: DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true),
    freshness: freshness,
    health: health,
  );
  snapshot.metrics = metrics;
  snapshot.error = error;
  return snapshot;
}

Metric percent(String value, {DateTime? resetsAt, String label = 'Uso'}) => Metric(
      kind: MetricKind.usedPercent,
      value: value,
      unit: MetricUnit.percent,
      scope: MetricScope.rollingWindow,
      availability: Availability.available,
      resetsAt: resetsAt,
      label: label,
    );

void main() {
  const presenter = OverlayPresenter();

  group('overlay projection', () {
    test('filters to visible kinds and skips remaining rows', () {
      final snapshot = snapshotWith(metrics: [
        Metric(
          kind: MetricKind.remainingPercent,
          value: '58',
          unit: MetricUnit.percent,
          scope: MetricScope.billingPeriod,
          availability: Availability.available,
          label: 'Restante',
        ),
        percent('42'),
        Metric(
          kind: MetricKind.balance,
          value: '42.50',
          unit: MetricUnit.usd,
          scope: MetricScope.currentBalance,
          availability: Availability.available,
          label: 'Saldo USD',
        ),
        Metric(
          kind: MetricKind.resourceMemory,
          value: '',
          unit: MetricUnit.bytes,
          scope: MetricScope.currentObservation,
          availability: Availability.unsupported,
          label: 'model',
        ),
      ]);
      final projection = projectOverlayRows([snapshot], DateTime.fromMillisecondsSinceEpoch(0, isUtc: true), 10);
      expect(projection.rows.map((r) => r.label), ['Uso', 'Saldo USD']);
      expect(projection.hiddenCount, 0);
    });

    test('status rows appear for non-fresh snapshots without metrics', () {
      final stale = snapshotWith(
        health: Health.error,
        freshness: Freshness.stale,
        error: ProviderError('timeout', 'No se pudo actualizar', transient: true),
      );
      final projection = projectOverlayRows([stale], DateTime.now(), 10);
      expect(projection.rows.single.label, 'Estado');
      expect(projection.rows.single.value, 'error · anterior');
    });

    test('unavailable metrics on a healthy fresh snapshot project no rows', () {
      final snapshot = snapshotWith(metrics: [
        Metric(
          kind: MetricKind.balance,
          value: '',
          unit: MetricUnit.unknown,
          scope: MetricScope.currentBalance,
          availability: Availability.unsupported,
          label: 'Saldo',
        ),
      ]);
      final projection = projectOverlayRows([snapshot], DateTime.fromMillisecondsSinceEpoch(0, isUtc: true), 10);
      // Healthy + fresh snapshots with no visible metrics get no status row.
      expect(projection.rows, isEmpty);
    });
  });

  group('capacity and hidden count', () {
    test('capacity math mirrors the reference', () {
      // Reference checks: OverlayRowCapacity(1000, 80, 32) == 10,
      // OverlayRowCapacity(100, 80, 32) == 0; 720/0/22 verified against the
      // C++ binary.
      expect(overlayRowCapacity(1000, 80, 32), 10);
      expect(overlayRowCapacity(100, 80, 32), 0);
      expect(overlayRowCapacity(720, 0, 22), 13);
      expect(overlayRowCapacity(0, 0, 22), 0);
      // fixedHeight >= maximum collapses to 0 (100*0.4=40 <= 40).
      expect(overlayRowCapacity(100, 40, 22), 0);
    });

    test('rows beyond capacity collapse to a hidden-count summary', () {
      final snapshots = [for (var i = 0; i < 20; i++) snapshotWith(id: 'p$i', name: 'P$i', metrics: [percent('10')])];
      final projection = projectOverlayRows(snapshots, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true), 5);
      expect(projection.rows, hasLength(4));
      expect(projection.hiddenCount, 16);
    });
  });

  group('countdown text and scheduling', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
    test('reset countdown formats mirror the reference', () {
      expect(formatResetCountdown(now.add(const Duration(seconds: 30)), now), 'reinicia en <1m');
      expect(formatResetCountdown(now.add(const Duration(minutes: 5)), now), 'reinicia en 5m');
      expect(formatResetCountdown(now.add(const Duration(minutes: 65)), now), 'reinicia en 1h 5m');
      expect(formatResetCountdown(now.add(const Duration(hours: 30)), now), 'reinicia en 1d 6h');
      expect(formatResetCountdown(now.subtract(const Duration(seconds: 1)), now), 'reiniciando');
      expect(formatResetCountdown(null, now), '');
    });

    test('unload countdown formats mirror the reference', () {
      expect(formatUnloadCountdown(now.add(const Duration(seconds: 30)), now), 'descarga en <1m');
      expect(formatUnloadCountdown(now.add(const Duration(minutes: 3)), now), 'descarga en 3m');
      expect(formatUnloadCountdown(now.subtract(const Duration(seconds: 2)), now), 'descargando');
    });

    OverlayRow rowWithReset(DateTime? resetsAt, String resetText) => OverlayRow(
          providerId: 'a',
          providerName: 'A',
          label: 'Uso',
          value: '5%',
          usedPercent: 5,
          resetsAt: resetsAt,
          resetText: resetText,
          statusText: '',
        );

    test('next update lands on the next minute boundary', () {
      final rows = [rowWithReset(now.add(const Duration(hours: 2)), 'reinicia en 120m')];
      final next = nextOverlayCountdownUpdate(rows, now);
      expect(next!.isBefore(now.add(const Duration(seconds: 61))), isTrue);
      expect(nextOverlayCountdownUpdate([rowWithReset(null, '')], now), isNull);
    });

    test('presenter detects repaint only when text changes', () {
      final reset = now.add(const Duration(minutes: 5));
      final rows = [rowWithReset(reset, formatResetCountdown(reset, now))];
      expect(presenter.shouldRepaintForCountdown(rows, now.add(const Duration(seconds: 10))), isFalse);
      expect(presenter.shouldRepaintForCountdown(rows, now.add(const Duration(minutes: 2))), isTrue);
    });
  });

  group('corner math', () {
    const monitor = OverlayMonitor(id: 'm1', isPrimary: true, left: 0, top: 0, width: 1920, height: 1080);

    test('anchors place the window at the requested corner', () {
      expect(
        presenter.anchorFor(OverlayCorner.topRight, monitor, 240, 160, 12),
        const Offset(1920 - 240 - 12, 12),
      );
      expect(
        presenter.anchorFor(OverlayCorner.bottomLeft, monitor, 240, 160, 12),
        const Offset(12, 1080 - 160 - 12),
      );
    });

    test('nearest corner is chosen by distance', () {
      expect(
        presenter.nearestCorner(
          windowPosition: const Offset(1900, 20),
          windowWidth: 240,
          windowHeight: 160,
          monitor: monitor,
          margin: 12,
        ),
        OverlayCorner.topRight,
      );
      expect(
        presenter.nearestCorner(
          windowPosition: const Offset(10, 10),
          windowWidth: 240,
          windowHeight: 160,
          monitor: monitor,
          margin: 12,
        ),
        OverlayCorner.topLeft,
      );
      expect(
        presenter.nearestCorner(
          windowPosition: const Offset(100, 1000),
          windowWidth: 240,
          windowHeight: 160,
          monitor: monitor,
          margin: 12,
        ),
        OverlayCorner.bottomLeft,
      );
      expect(
        presenter.nearestCorner(
          windowPosition: const Offset(1700, 900),
          windowWidth: 240,
          windowHeight: 160,
          monitor: monitor,
          margin: 12,
        ),
        OverlayCorner.bottomRight,
      );
    });
  });

  group('monitor fallback and selection', () {
    test('saved monitor wins when available', () {
      final saved = OverlayMonitor(id: 'm2', isPrimary: false, left: 0, top: 0, width: 800, height: 600);
      final primary = OverlayMonitor(id: 'm1', isPrimary: true, left: 0, top: 0, width: 1920, height: 1080);
      expect(presenter.selectMonitor('m2', [primary, saved]), saved);
      expect(presenter.selectMonitor('gone', [primary, saved]), primary);
      expect(presenter.selectMonitor('gone', [saved]), saved);
      expect(presenter.selectMonitor('gone', []), isNull);
      expect(presenter.selectMonitor('', [saved]), saved);
    });

    test('placement anchor clamps into the work area', () {
      final monitor = OverlayMonitor(id: 'm1', isPrimary: true, left: 100, top: 50, width: 800, height: 600);
      final clamped = presenter.clampOnScreen(
        const Offset(900, 700),
        monitor,
        240,
        160,
        12,
      );
      expect(clamped.dx, lessThanOrEqualTo(100 + 800 - 240));
      expect(clamped.dy, lessThanOrEqualTo(50 + 600 - 160));
      expect(clamped.dx, greaterThanOrEqualTo(100));
      expect(clamped.dy, greaterThanOrEqualTo(50));
    });
  });

  group('opacity clamping', () {
    test('configured opacity clamps to 50..100', () {
      final overlay = OverlaySettings(opacity: 10);
      expect(presenter.normalizedOpacity(overlay), 50);
      overlay.opacity = 200;
      expect(presenter.normalizedOpacity(overlay), 100);
      overlay.opacity = 78;
      expect(presenter.normalizedOpacity(overlay), 78);
    });

    test('hover raises to at least 95', () {
      expect(presenter.hoveredOpacity(50), 95);
      expect(presenter.hoveredOpacity(78), 95);
      expect(presenter.hoveredOpacity(96), 96);
      expect(presenter.hoveredOpacity(100), 100);
    });
  });

  testWidgets('panel renders rows, progress and summary', (tester) async {
    const rows = [
      OverlayRow(
        providerId: 'a',
        providerName: 'Codex',
        label: 'Codex principal',
        value: '42%',
        usedPercent: 42,
        resetsAt: null,
        resetText: 'reinicia en 5m',
        statusText: '',
      ),
    ];
    await tester.pumpWidget(
      const ThemeOverride(
        brightness: Brightness.dark,
        child: MaterialApp(
          home: Scaffold(
            body: OverlayPanel(
              projection: OverlayProjection(rows: rows, hiddenCount: 3),
              opacity: 78,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Codex · Codex principal'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('reinicia en 5m'), findsOneWidget);
    expect(find.text('+3 más'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}