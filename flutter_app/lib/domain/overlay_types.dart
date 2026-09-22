/// Overlay projection types shared between config, presentation and ui layers.
library;

/// Corner anchor of the overlay within a monitor work area.
enum OverlayCorner {
  topLeft('top-left'),
  topRight('top-right'),
  bottomLeft('bottom-left'),
  bottomRight('bottom-right');

  const OverlayCorner(this.wire);

  final String wire;

  static OverlayCorner parse(String text) {
    for (final value in OverlayCorner.values) {
      if (value.wire == text) return value;
    }
    return OverlayCorner.topRight;
  }
}

/// One projected row of the minimal overlay.
class OverlayRow {
  const OverlayRow({
    required this.providerId,
    required this.providerName,
    required this.label,
    required this.value,
    required this.usedPercent,
    required this.resetsAt,
    required this.resetText,
    required this.statusText,
  });

  final String providerId;
  final String providerName;
  final String label;
  final String value;
  final double? usedPercent;
  final DateTime? resetsAt;
  final String resetText;
  final String statusText;
}

/// Result of projecting snapshots into overlay rows.
class OverlayProjection {
  const OverlayProjection({List<OverlayRow>? rows, this.hiddenCount = 0}) : rows = rows ?? const <OverlayRow>[];

  final List<OverlayRow> rows;
  final int hiddenCount;
}