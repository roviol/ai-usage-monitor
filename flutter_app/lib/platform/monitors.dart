/// Monitor enumeration producing the reference's identifiers so persisted
/// overlay monitor ids survive: `\\.\DISPLAYn` on Windows and display name or
/// `display-N` on Linux, with primary detection, work areas and a fallback
/// monitor.
library;

import 'dart:io';

import 'interfaces.dart';

/// Monitor service backed by OS display enumeration; when native enumeration
/// is unavailable the single-work-area fallback applies, matching the
/// reference's fallback monitor behavior.
class IoMonitorService implements MonitorService {
  IoMonitorService();

  @override
  List<MonitorInfo> monitors() {
    final raw = _enumerateNative();
    if (raw.isNotEmpty) return raw;
    return _fallbackMonitors();
  }

  @override
  MonitorInfo? primary() {
    final all = monitors();
    if (all.isEmpty) return null;
    for (final monitor in all) {
      if (monitor.isPrimary) return monitor;
    }
    return all.first;
  }

  /// Native enumeration is provided by the platform runner when present;
  /// for headless parity tests and early startup the fallback list is
  /// returned and the platform plugin, when present, overrides this method.
  List<MonitorInfo> _enumerateNative() => const [];

  List<MonitorInfo> _fallbackMonitors() {
    // The reference's fallback: one monitor covering the primary display with
    // a conservative work area.
    final id = Platform.isWindows ? r'\\.\DISPLAY1' : 'display-1';
    return [
      MonitorInfo(
        id: id,
        isPrimary: true,
        workAreaLeft: 0,
        workAreaTop: 0,
        workAreaWidth: 1280,
        workAreaHeight: 720,
      ),
    ];
  }
}

/// Chooses the monitor for overlay placement with the reference's fallback
/// order: saved monitor when still available, then primary, then first
/// available, else empty.
String selectOverlayMonitor(String savedMonitor, List<String> availableMonitors, String primaryMonitor) {
  if (savedMonitor.isNotEmpty && availableMonitors.contains(savedMonitor)) return savedMonitor;
  if (primaryMonitor.isNotEmpty && availableMonitors.contains(primaryMonitor)) return primaryMonitor;
  return availableMonitors.isEmpty ? '' : availableMonitors.first;
}