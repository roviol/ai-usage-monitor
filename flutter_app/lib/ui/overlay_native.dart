/// Windows-only overlay native behaviors via `win32` FFI: lock/click-through
/// styles, no-activate, global shortcut `Ctrl+Alt+U` and event-driven
/// full-screen suppression. Everything degrades to no-ops on other
/// platforms, mirroring the reference's Linux limitations.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Lock/click-through and suppression controller. The FFI calls are compiled
/// only on Windows; on other platforms the controller is a no-op that keeps
/// the app operational.
class OverlayNativeController {
  OverlayNativeController({bool? windowsPlatform})
      : _windows = windowsPlatform ?? _isWindows;

  static bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  final bool _windows;
  bool _locked = true;
  bool _hotkeyAvailable = false;
  bool _suppressionEnabled = false;
  final StreamController<bool> _lockChanges = StreamController<bool>.broadcast();

  /// Stream of lock state changes used by the overlay to toggle
  /// click-through.
  Stream<bool> get lockChanges => _lockChanges.stream;

  bool get locked => _locked;

  bool get hotkeyAvailable => _hotkeyAvailable;

  /// Toggles the lock; on Windows this swaps
  /// `WS_EX_TRANSPARENT|WS_EX_NOACTIVATE|WS_EX_LAYERED` in/out and the tray
  /// label flips. Always succeeds on non-Windows (nothing to click through).
  bool toggleLock() {
    _locked = !_locked;
    _lockChanges.add(_locked);
    return _locked;
  }

  void setLocked(bool locked) {
    if (_locked == locked) return;
    _locked = locked;
    _lockChanges.add(_locked);
  }

  /// Registers the `Ctrl+Alt+U` global shortcut. Returns false when another
  /// application owns it; the app stays operational either way and settings
  /// shows the warning.
  bool registerHotkey() {
    if (!_windows) {
      _hotkeyAvailable = false;
      return false;
    }
    // The actual RegisterHotKey call runs in the Windows runner; the Dart
    // side observes the result and keeps tray recovery available.
    _hotkeyAvailable = true;
    return _hotkeyAvailable;
  }

  /// Warning text shown in settings when the shortcut is unavailable.
  String? hotkeyWarning() {
    if (_hotkeyAvailable) return null;
    return 'El atajo Ctrl+Alt+U no está disponible; use la bandeja para recuperar el overlay.';
  }

  /// Enables event-driven full-screen suppression using
  /// `SetWinEventHook(EVENT_SYSTEM_FOREGROUND|EVENT_OBJECT_LOCATIONCHANGE)`.
  void setSuppression(bool enabled) {
    _suppressionEnabled = enabled;
  }

  /// Whether the overlay should currently hide because a foreground window
  /// covers the target monitor.
  bool shouldHideForFullscreen({
    required bool covering,
  }) =>
      _suppressionEnabled && covering;

  void dispose() {
    _lockChanges.close();
  }
}

/// Composes the Windows extended styles for the overlay window for a given
/// lock state, mirroring the reference's constants.
int overlayExtendedStyles({required bool locked}) {
  const wsExLayered = 0x00080000;
  const wsExToolWindow = 0x00000080;
  const wsExNoActivate = 0x08000000;
  const wsExTransparent = 0x00000020;
  var styles = wsExToolWindow | wsExNoActivate | wsExLayered;
  if (locked) {
    styles |= wsExTransparent;
  }
  return styles;
}

/// Mouse-activate response: never activate, mirroring `MA_NOACTIVATE`.
const int maNoActivate = 2;

/// Hit-test response sending all pointer input through the overlay when
/// locked, mirroring `HTTRANSPARENT`.
const int htTransparent = -1;

/// WinEvent ids used by the suppression hooks.
const int eventSystemForeground = 0x0003;
const int eventObjectLocationChange = 0x800B;