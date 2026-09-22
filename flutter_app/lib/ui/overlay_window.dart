/// Minimal overlay window ported from `src/ui/overlay_frame.cpp`: frameless
/// always-on-top skip-taskbar window with buffered custom painting, rows,
/// progress tracks, opacity hover raise, drag-to-corner snapping and
/// countdown scheduling limited to formatted-minute changes.
///
/// The pure placement/opacity/countdown math lives in [OverlayPresenter] so
/// the window logic is testable without the plugin layer.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../config/settings.dart';
import '../config/validation.dart';
import '../domain/model.dart';
import '../domain/overlay_types.dart';
import '../presentation/presentation.dart';
import 'theme.dart';

/// Monitor geometry abstraction used by the overlay placement math.
class OverlayMonitor {
  const OverlayMonitor({
    required this.id,
    required this.isPrimary,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String id;
  final bool isPrimary;
  final int left;
  final int top;
  final int width;
  final int height;
}

/// Stateful presentation layer of the overlay: opacity normalization, hover
/// raise, corner anchoring, on-screen clamping, monitor selection and
/// countdown scheduling decisions.
class OverlayPresenter {
  const OverlayPresenter();

  /// Applies the persisted opacity normalization to a settings value.
  int normalizedOpacity(OverlaySettings overlay) => normalizeOverlayOpacity(overlay.opacity);

  /// Opacity while hovered: at least 95 percent.
  int hoveredOpacity(int configured) {
    final normalized = normalizeOverlayOpacity(configured);
    return normalized < 95 ? 95 : normalized;
  }

  /// Anchor offset for a corner inside the monitor work area with margins.
  Offset anchorFor(
    OverlayCorner corner,
    OverlayMonitor monitor,
    int windowWidth,
    int windowHeight,
    int margin,
  ) {
    final marginNorm = normalizeOverlayMargin(margin);
    return switch (corner) {
      OverlayCorner.topLeft => Offset((monitor.left + marginNorm).toDouble(), (monitor.top + marginNorm).toDouble()),
      OverlayCorner.topRight => Offset(
          (monitor.left + monitor.width - windowWidth - marginNorm).toDouble(),
          (monitor.top + marginNorm).toDouble(),
        ),
      OverlayCorner.bottomLeft => Offset(
          (monitor.left + marginNorm).toDouble(),
          (monitor.top + monitor.height - windowHeight - marginNorm).toDouble(),
        ),
      OverlayCorner.bottomRight => Offset(
          (monitor.left + monitor.width - windowWidth - marginNorm).toDouble(),
          (monitor.top + monitor.height - windowHeight - marginNorm).toDouble(),
        ),
    };
  }

  /// Clamps a window position fully inside the monitor work area.
  Offset clampOnScreen(
    Offset position,
    OverlayMonitor monitor,
    int windowWidth,
    int windowHeight,
    int margin,
  ) {
    final maxX = monitor.left + monitor.width - windowWidth;
    final maxY = monitor.top + monitor.height - windowHeight;
    return Offset(
      position.dx.clamp(monitor.left.toDouble(), math.max(monitor.left.toDouble(), maxX.toDouble())),
      position.dy.clamp(monitor.top.toDouble(), math.max(monitor.top.toDouble(), maxY.toDouble())),
    );
  }

  /// Selects the monitor with the reference's fallback order: saved monitor
  /// when still available, then primary, then first, else null.
  OverlayMonitor? selectMonitor(String savedMonitor, List<OverlayMonitor> monitors) {
    for (final monitor in monitors) {
      if (savedMonitor.isNotEmpty && monitor.id == savedMonitor) return monitor;
    }
    for (final monitor in monitors) {
      if (monitor.isPrimary) return monitor;
    }
    return monitors.isEmpty ? null : monitors.first;
  }

  /// The corner nearest to a window position inside a work area.
  OverlayCorner nearestCorner({
    required Offset windowPosition,
    required int windowWidth,
    required int windowHeight,
    required OverlayMonitor monitor,
    required int margin,
  }) =>
      nearestOverlayCorner(
        windowPosition.dx.round(),
        windowPosition.dy.round(),
        windowWidth,
        windowHeight,
        monitor.left,
        monitor.top,
        monitor.left + monitor.width,
        monitor.top + monitor.height,
        margin,
      );

  /// Whether a countdown repaint is due: only when the formatted text would
  /// change, mirroring the no-idle-polling requirement.
  bool shouldRepaintForCountdown(List<OverlayRow> rows, DateTime now) {
    for (final row in rows) {
      final reset = row.resetsAt;
      if (reset == null) continue;
      final current = formatResetCountdown(reset, now);
      if (current.isNotEmpty && current != row.resetText) return true;
    }
    return false;
  }

  /// The next scheduled update time for countdowns.
  DateTime? nextUpdate(List<OverlayRow> rows, DateTime now) => nextOverlayCountdownUpdate(rows, now);
}

/// The overlay panel: buffered rows with progress tracks and the
/// additional-count summary; no continuous animation.
class OverlayPanel extends StatelessWidget {
  const OverlayPanel({super.key, required this.projection, required this.opacity});

  final OverlayProjection projection;
  final int opacity;

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeOverride.maybeOf(context) ?? Brightness.dark;
    final dark = brightness == Brightness.dark;
    final background = (dark ? Colors.black : Colors.white).withValues(alpha: opacity / 100.0);
    final text = dark ? Colors.white : Colors.black;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in projection.rows) ..._row(row, text),
            if (projection.hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+${projection.hiddenCount} más',
                  style: TextStyle(color: text.withValues(alpha: 0.7), fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> _row(OverlayRow row, Color text) sync* {
    yield Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${row.providerName} · ${row.label}',
              style: TextStyle(color: text, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 48,
            child: Text(
              row.value,
              style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
    if (row.usedPercent != null) {
      yield Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            value: row.usedPercent! / 100.0,
            minHeight: 2,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );
    }
    if (row.resetText.isNotEmpty) {
      yield Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 2),
        child: Text(
          row.resetText,
          style: TextStyle(color: text.withValues(alpha: 0.75), fontSize: 10),
        ),
      );
    }
  }
}

/// Hosts the overlay panel: drag, hover opacity raise and countdown
/// scheduling; the window flags (frameless, topmost, skip-taskbar) are
/// applied by the host at startup.
class OverlayWindow extends StatefulWidget {
  const OverlayWindow({
    super.key,
    required this.snapshots,
    required this.overlay,
    required this.monitors,
    this.onPersist,
    this.windowsPlatform = false,
  });

  final List<ProviderSnapshot> snapshots;
  final OverlaySettings overlay;
  final List<OverlayMonitor> monitors;
  final bool windowsPlatform;

  /// Called when drag ends so the app can persist monitor/corner.
  final void Function(OverlaySettings overlay)? onPersist;

  @override
  State<OverlayWindow> createState() => _OverlayWindowState();
}

class _OverlayWindowState extends State<OverlayWindow> {
  final OverlayPresenter presenter = const OverlayPresenter();
  static const _windowWidth = 240;
  static const _windowHeight = 160;

  bool _hovering = false;
  Offset _windowPosition = Offset.zero;
  Timer? _countdownTimer;
  String _lastCountdownText = '';

  @override
  void initState() {
    super.initState();
    _restorePlacement();
    _scheduleCountdown();
  }

  void _restorePlacement() {
    final monitor = presenter.selectMonitor(widget.overlay.monitor, widget.monitors);
    if (monitor == null) return;
    _windowPosition = presenter.anchorFor(
      widget.overlay.corner,
      monitor,
      _windowWidth,
      _windowHeight,
      widget.overlay.margin,
    );
    unawaited(windowManager.setPosition(_windowPosition));
  }

  void _scheduleCountdown() {
    _countdownTimer?.cancel();
    final now = DateTime.now();
    final capacity = overlayRowCapacity(720, fixedOverlayHeight, 22);
    final projection = projectOverlayRows(widget.snapshots, now, capacity);
    final next = presenter.nextUpdate(projection.rows, now);
    if (next == null) return;
    final delay = next.difference(now);
    _countdownTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      final currentNow = DateTime.now();
      final currentProjection = projectOverlayRows(widget.snapshots, currentNow, capacity);
      final nextText = currentProjection.rows.map((r) => r.resetText).join('|');
      if (nextText != _lastCountdownText) {
        setState(() {
          _lastCountdownText = nextText;
        });
      }
      _scheduleCountdown();
    });
  }

  int get _opacity {
    final configured = presenter.normalizedOpacity(widget.overlay);
    return _hovering ? presenter.hoveredOpacity(configured) : configured;
  }

  void _onDrag(DragUpdateDetails details) {
    final monitor = presenter.selectMonitor(widget.overlay.monitor, widget.monitors);
    if (monitor == null) return;
    setState(() {
      _windowPosition = presenter.clampOnScreen(
        _windowPosition + details.delta,
        monitor,
        _windowWidth,
        _windowHeight,
        widget.overlay.margin,
      );
    });
    unawaited(windowManager.setPosition(_windowPosition));
  }

  void _snapToCorner() {
    final monitor = presenter.selectMonitor(widget.overlay.monitor, widget.monitors);
    if (monitor == null) return;
    final corner = presenter.nearestCorner(
      windowPosition: _windowPosition,
      windowWidth: _windowWidth,
      windowHeight: _windowHeight,
      monitor: monitor,
      margin: widget.overlay.margin,
    );
    setState(() {
      widget.overlay.corner = corner;
      widget.overlay.monitor = monitor.id;
      _windowPosition = presenter.anchorFor(
        corner,
        monitor,
        _windowWidth,
        _windowHeight,
        widget.overlay.margin,
      );
    });
    unawaited(windowManager.setPosition(_windowPosition));
    widget.onPersist?.call(widget.overlay);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final capacity = overlayRowCapacity(720, fixedOverlayHeight, 22);
    final projection = projectOverlayRows(widget.snapshots, now, capacity);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _onDrag,
        onPanEnd: (_) => _snapToCorner(),
        child: OverlayPanel(projection: projection, opacity: _opacity),
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}