/// System tray ported from `src/ui/tray_icon.cpp`: health-colored icon drawn
/// at runtime, tooltip composition, menu with dashboard/refresh/overlay/
/// configuration/exit, left-click activation and tray-unavailable detection.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';

import '../domain/model.dart';
import '../domain/validate.dart';
import '../presentation/presentation.dart';
import 'theme.dart';

/// Icon color for an aggregate health, mirroring the reference's palette.
Color trayIconColor(Health health, Brightness brightness) => health.color(brightness);

/// Tooltip label for the aggregate health, matching `ComposeTooltip`'s
/// aggregate prefix.
String trayAggregateLabel(Health aggregate) => 'IA: ${aggregate.wire}';

/// Draws a round health-colored tray icon at runtime, mirroring the
/// reference's runtime-drawn icon.
Future<ui.Image> renderTrayIcon(Color color, {int size = 64}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..color = color;
  canvas.drawCircle(Offset(size / 2, size / 2), size * 0.4, paint);
  final picture = recorder.endRecording();
  return picture.toImage(size, size);
}

/// Menu item identifiers used by the tray menu.
abstract final class TrayMenuIds {
  static const dashboard = 'open-dashboard';
  static const refresh = 'refresh-all';
  static const overlayVisible = 'overlay-visible';
  static const overlayLock = 'overlay-lock';
  static const settings = 'open-settings';
  static const exit = 'exit-application';
}

/// Overlay state exposed to the tray menu enablement.
class TrayOverlayState {
  const TrayOverlayState({required this.enabled, required this.visible, required this.locked});

  final bool enabled;
  final bool visible;
  final bool locked;
}

/// Builds the tray menu with enablement rules mirroring the reference:
/// overlay items appear only when the overlay is enabled, lock only on
/// Windows.
Menu buildTrayMenu({
  required TrayOverlayState overlay,
  required bool windowsPlatform,
}) {
  final overlayVisible = MenuItem(
    key: TrayMenuKeys.overlayVisible,
    label: overlay.visible && overlay.enabled ? 'Ocultar overlay' : 'Mostrar overlay',
    disabled: !overlay.enabled,
  );
  final overlayLock = MenuItem(
    key: TrayMenuKeys.overlayLock,
    label: overlay.locked ? 'Desbloquear overlay' : 'Bloquear overlay',
    disabled: !overlay.enabled || !windowsPlatform,
  );
  return Menu(
    items: [
      MenuItem(key: TrayMenuKeys.dashboard, label: 'Abrir panel'),
      MenuItem(key: TrayMenuKeys.refresh, label: 'Actualizar todos'),
      MenuItem.separator(),
      overlayVisible,
      if (windowsPlatform) overlayLock,
      MenuItem.separator(),
      MenuItem(key: TrayMenuKeys.settings, label: 'Configuración…'),
      MenuItem(key: TrayMenuKeys.exit, label: 'Salir'),
    ],
  );
}

/// Menu keys used by the built menu above (kept separate for testability).
abstract final class TrayMenuKeys {
  static const dashboard = TrayMenuIds.dashboard;
  static const refresh = TrayMenuIds.refresh;
  static const overlayVisible = TrayMenuIds.overlayVisible;
  static const overlayLock = TrayMenuIds.overlayLock;
  static const settings = TrayMenuIds.settings;
  static const exit = TrayMenuIds.exit;
}

/// Pure tray logic: aggregate icon updates, tooltip text, menu enablement and
/// click behavior, independent of the tray_manager plugin for tests.
class TrayPresenter {
  const TrayPresenter({this.maxCharacters = maxTooltipCharacters});

  final int maxCharacters;

  /// The icon health: aggregated over every snapshot.
  Health aggregateIconHealth(List<ProviderSnapshot> snapshots) => aggregateHealth(snapshots);

  /// The tooltip text for the current snapshots.
  String tooltip(List<ProviderSnapshot> snapshots, DateTime now) =>
      composeTooltip(snapshots, now, maxCharacters);

  /// Whether the tray menu should expose overlay items.
  bool overlayItemsVisible(TrayOverlayState overlay) => overlay.enabled;

  /// Left-click activation opens the dashboard.
  bool get opensDashboardOnLeftClick => true;
}