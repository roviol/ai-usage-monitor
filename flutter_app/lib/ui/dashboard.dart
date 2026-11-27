/// Dashboard widgets: app bar, responsive grid and provider cards, ported
/// from `src/ui/dashboard.cpp` with equivalent Spanish status text.
library;

import 'package:flutter/material.dart';

import '../domain/model.dart';
import '../presentation/presentation.dart';
import 'theme.dart';

/// Dashboard app bar with title, refresh and settings actions.
class DashboardAppBar extends AppBar {
  DashboardAppBar({
    super.key,
    required VoidCallback onRefresh,
    required VoidCallback onSettings,
  }) : super(
          title: const Text('AI Usage Monitor'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
            ),
            IconButton(
              tooltip: 'Configuración',
              icon: const Icon(Icons.settings),
              onPressed: onSettings,
            ),
          ],
        );
}

/// Responsive grid: 400-logical-pixel minimum cell with 12-pixel margins,
/// growing columns with width, single column when compact.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({super.key, required this.children});

  final List<Widget> children;

  static int columnsFor(double width, {double minWidth = Spacing.cardMinWidth, double margin = Spacing.gridMargin}) {
    final usable = width - 2 * margin;
    if (usable < minWidth) return 1;
    return (usable / (minWidth + margin)).floor().clamp(1, 16);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = columnsFor(width);
    if (columns <= 1) {
      return ListView(
        padding: const EdgeInsets.all(Spacing.gridMargin),
        children: children,
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final row = children.sublist(i, (i + columns).clamp(0, children.length));
      while (row.length < columns) {
        row.add(const SizedBox());
      }
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cell in row)
            Expanded(
              child: cell is SizedBox ? cell : Padding(padding: const EdgeInsets.all(Spacing.sm), child: cell),
            ),
        ],
      ));
    }
    return ListView(
      padding: const EdgeInsets.all(Spacing.gridMargin),
      children: rows,
    );
  }
}

/// One provider card with health pill, observation line, account line,
/// metric rows, percentage progress and error notices, applying the
/// reference card filtering rules.
class ProviderCard extends StatelessWidget {
  const ProviderCard({super.key, required this.snapshot, this.refreshing = false});

  final ProviderSnapshot snapshot;
  final bool refreshing;

  /// The reference's card filtering: percentage rows for cards, balance and
  /// derived spend, token counts; excluding remaining-percentage rows,
  /// per-model memory and request counts.
  static List<Metric> cardMetrics(ProviderSnapshot snapshot) {
    final visible = <Metric>[];
    for (final metric in snapshot.metrics) {
      final show = switch (metric.kind) {
        MetricKind.usedPercent ||
        MetricKind.balance ||
        MetricKind.spent ||
        MetricKind.totalTokens ||
        MetricKind.loadedModels =>
          true,
        _ => false,
      };
      if (show) visible.add(metric);
    }
    return visible;
  }

  String _freshnessText() {
    return switch (snapshot.freshness) {
      Freshness.fresh => 'al día',
      Freshness.stale => 'datos anteriores',
      Freshness.noData => 'sin datos',
    };
  }

  String _healthText() {
    return switch (snapshot.health) {
      Health.healthy => 'Conectado',
      Health.partial => 'Parcial',
      Health.error => 'Error',
      Health.disabled => 'Desactivado',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = ThemeOverride.maybeOf(context) ?? theme.brightness;
    final metrics = cardMetrics(snapshot);
    final error = snapshot.error;
    final refreshingNotice = error?.code == 'refreshing';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: snapshot.health.color(brightness).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    _healthText(),
                    style: TextStyle(
                      color: snapshot.health.color(brightness),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_freshnessText()} · ${ageText(snapshot, DateTime.now())}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(snapshot.displayName, style: theme.textTheme.titleMedium),
            if (snapshot.accountLabel.isNotEmpty)
              Text(snapshot.accountLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: Spacing.sm),
            if (metrics.isEmpty)
              Text(
                'No hay métricas disponibles',
                style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              )
            else
              ...[
                for (final metric in metrics) ..._metricRow(context, metric),
              ],
            if (refreshingNotice)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  error!.message,
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              )
            else if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  error.message,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> _metricRow(BuildContext context, Metric metric) sync* {
    final theme = Theme.of(context);
    final percent = metric.unit == MetricUnit.percent && metric.availability == Availability.available
        ? double.tryParse(metric.value)?.clamp(0.0, 100.0)
        : null;
    yield Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(metric.label, style: theme.textTheme.bodyMedium)),
          Text(formatMetric(metric), style: theme.textTheme.bodyMedium),
        ],
      ),
    );
    if (percent != null) {
      yield Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: LinearProgressIndicator(
          value: percent / 100.0,
          minHeight: 4,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      );
    }
    if (metric.kind == MetricKind.usedPercent && metric.provenance == Provenance.derived) {
      yield Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Text('derivado', style: theme.textTheme.labelSmall),
      );
    }
  }
}

/// Dashboard body with empty/loading states and the reference's Spanish
/// notices.
class DashboardBody extends StatelessWidget {
  const DashboardBody({super.key, required this.snapshots});

  final List<ProviderSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    if (snapshots.isEmpty) {
      return const Center(child: Text('No hay proveedores configurados'));
    }
    return ResponsiveCardGrid(
      children: [
        for (final snapshot in snapshots) ProviderCard(snapshot: snapshot),
      ],
    );
  }
}

/// Assembles the dashboard scaffold around the grid and notices.
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.snapshots,
    required this.onRefresh,
    required this.onSettings,
    this.trayUnavailable = false,
  });

  final List<ProviderSnapshot> snapshots;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final bool trayUnavailable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: DashboardAppBar(onRefresh: onRefresh, onSettings: onSettings),
      body: Column(
        children: [
          if (trayUnavailable)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(Spacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded),
                    SizedBox(width: Spacing.sm),
                    Expanded(child: Text('La bandeja del sistema no está disponible.')),
                  ],
                ),
              ),
            ),
          Expanded(child: DashboardBody(snapshots: snapshots)),
        ],
      ),
    );
  }
}