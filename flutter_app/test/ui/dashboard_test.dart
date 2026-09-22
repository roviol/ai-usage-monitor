import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/domain/model.dart';
import 'package:ai_usage_monitor/ui/dashboard.dart';
import 'package:ai_usage_monitor/ui/theme.dart';

ProviderSnapshot snapshotOf({
  String id = 'a',
  String name = 'Provider A',
  Health health = Health.healthy,
  Freshness freshness = Freshness.fresh,
  String? account,
  List<Metric>? metrics,
  ProviderError? error,
}) {
  final snapshot = ProviderSnapshot(
    providerId: id,
    displayName: name,
    observedAt: DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true),
    freshness: freshness,
    health: health,
    accountLabel: account ?? '',
  );
  snapshot.metrics = metrics ?? <Metric>[];
  snapshot.error = error;
  return snapshot;
}

Metric percentMetric({String value = '42', String label = 'Uso'}) => Metric(
      kind: MetricKind.usedPercent,
      value: value,
      unit: MetricUnit.percent,
      scope: MetricScope.billingPeriod,
      availability: Availability.available,
      label: label,
    );

void main() {
  group('ResponsiveCardGrid columns', () {
    test('column math matches the reference', () {
      expect(ResponsiveCardGrid.columnsFor(320), 1);
      expect(ResponsiveCardGrid.columnsFor(400), 1);
      expect(ResponsiveCardGrid.columnsFor(832), 1);
      expect(ResponsiveCardGrid.columnsFor(860), 2);
      expect(ResponsiveCardGrid.columnsFor(1280), 3);
      expect(ResponsiveCardGrid.columnsFor(1700), 4);
    });

    testWidgets('wide window lays out multiple columns', (tester) async {
      tester.view.physicalSize = const Size(1700, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveCardGrid(
              children: [
                ProviderCard(snapshot: snapshotOf(id: 'a', name: 'A')),
                ProviderCard(snapshot: snapshotOf(id: 'b', name: 'B')),
                ProviderCard(snapshot: snapshotOf(id: 'c', name: 'C')),
                ProviderCard(snapshot: snapshotOf(id: 'd', name: 'D')),
              ],
            ),
          ),
        ),
      );
      final rows = tester.widgetList<Row>(find.byType(Row));
      expect(rows, isNotEmpty);
    });

    testWidgets('compact window uses a single readable column', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveCardGrid(
              children: [
                ProviderCard(snapshot: snapshotOf(id: 'a', name: 'A')),
                ProviderCard(snapshot: snapshotOf(id: 'b', name: 'B')),
              ],
            ),
          ),
        ),
      );
      // Compact: ListView, no outer Rows from the grid path.
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(ProviderCard), findsNWidgets(2));
    });
  });

  group('ProviderCard content', () {
    testWidgets('healthy card shows status, observation and metrics', (tester) async {
      final snapshot = snapshotOf(
        account: 'cuenta@example.com',
        metrics: [percentMetric()],
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProviderCard(snapshot: snapshot))));
      expect(find.text('Conectado'), findsOneWidget);
      expect(find.text('Provider A'), findsOneWidget);
      expect(find.text('cuenta@example.com'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('disabled card shows disabled status without error', (tester) async {
      final snapshot = snapshotOf(health: Health.disabled);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProviderCard(snapshot: snapshot))));
      expect(find.text('Desactivado'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('no displayable metrics shows the notice', (tester) async {
      final snapshot = snapshotOf(
        metrics: [
          Metric(
            kind: MetricKind.remainingPercent,
            value: '58',
            unit: MetricUnit.percent,
            scope: MetricScope.billingPeriod,
            availability: Availability.available,
            label: 'Restante',
          ),
          Metric(
            kind: MetricKind.resourceMemory,
            value: '100',
            unit: MetricUnit.bytes,
            scope: MetricScope.currentObservation,
            availability: Availability.available,
            label: 'model',
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProviderCard(snapshot: snapshot))));
      expect(find.text('No hay métricas disponibles'), findsOneWidget);
    });

    testWidgets('refreshing shows accent notice instead of error', (tester) async {
      final snapshot = snapshotOf(
        freshness: Freshness.stale,
        error: ProviderError('refreshing', 'Actualizando…', transient: true),
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProviderCard(snapshot: snapshot))));
      expect(find.text('Actualizando…'), findsOneWidget);
    });

    testWidgets('error card shows the error notice', (tester) async {
      final snapshot = snapshotOf(
        health: Health.error,
        error: ProviderError('unauthorized', 'Revise la credencial configurada.', transient: false),
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProviderCard(snapshot: snapshot))));
      expect(find.text('Revise la credencial configurada.'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
    });
  });

  group('DashboardBody and app bar', () {
    testWidgets('empty configuration shows the empty notice', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DashboardBody(snapshots: []))));
      expect(find.text('No hay proveedores configurados'), findsOneWidget);
    });

    testWidgets('app bar exposes refresh and settings actions', (tester) async {
      var refreshed = false;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardPage(
            snapshots: const [],
            onRefresh: () => refreshed = true,
            onSettings: () => opened = true,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.tap(find.byIcon(Icons.settings));
      expect(refreshed, isTrue);
      expect(opened, isTrue);
    });

    testWidgets('tray-unavailable notice appears when flagged', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardPage(
            snapshots: const [],
            onRefresh: () {},
            onSettings: () {},
            trayUnavailable: true,
          ),
        ),
      );
      expect(find.text('La bandeja del sistema no está disponible.'), findsOneWidget);
    });
  });

  group('theme', () {
    test('compact layout breakpoint mirrors the reference', () {
      expect(useCompactLayout(640), isFalse);
      expect(useCompactLayout(639), isTrue);
      expect(useCompactLayout(460), isTrue);
      expect(useCompactLayout(800), isFalse);
    });

    test('contrast adjustment keeps readable text', () {
      const muted = PresentationRgb(200, 200, 200);
      const white = PresentationRgb(255, 255, 255);
      expect(contrastRatio(muted, white), lessThan(4.5));
      final corrected = ensureTextContrast(muted, white);
      expect(contrastRatio(corrected, white), greaterThanOrEqualTo(4.5));
    });

    test('dpi scaling matches the reference', () {
      expect(scaleForDpi(440, 100), 440);
      expect(scaleForDpi(440, 125), 550);
      expect(scaleForDpi(440, 150), 660);
      expect(scaleForDpi(440, 200), 880);
      expect(scaleForDpi(0, 200), 0);
    });
  });
}