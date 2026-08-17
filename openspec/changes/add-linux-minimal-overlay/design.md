## Context

`MinimalOverlayFrame` (`src/ui/overlay_frame.cpp`) exists today only inside a
top-to-bottom `#ifdef _WIN32 ... #endif` block. Its pure math/formatting —
opacity/margin clamping, nearest-corner snapping, countdown scheduling,
row projection — already lives in platform-independent `src/overlay.cpp` /
`include/ai_usage/overlay.h` and needs no changes. What's Windows-only is:
monitor enumeration (`HMONITOR`/`EnumDisplayMonitors`), window positioning
(`SetWindowPos`/`HWND_TOPMOST`), layered-window opacity
(`SetLayeredWindowAttributes`), click-through (`WS_EX_TRANSPARENT` +
`WM_NCHITTEST`), the global recovery hotkey (`RegisterHotKey`), and
foreground/fullscreen detection (`SetWinEventHook`). The paint routine
(`OnPaint`) and drag/mouse handlers are already written in portable wx calls
but are physically inside the same `#ifdef` block, so they're unavailable on
Linux today even though nothing in them is Windows-specific.

## Goals / Non-Goals

**Goals:**
- A working, visually-consistent overlay on Linux (X11 primarily; best-effort
  on Wayland/GNOME per existing docs caveat) for: show/hide, drag-to-corner
  placement with multi-monitor recovery, configurable opacity with hover
  brighten/fade, using the same row rendering as Windows.
- Zero changes to the portable engine (`overlay.h`/`overlay.cpp`) or to
  `OverlaySettings` — both are already platform-neutral.
- Minimal risk to the existing, already-shipped Windows overlay: don't
  restructure its working code path to "unify" it with Linux in this change.

**Non-Goals:**
- Click-through lock, global hotkey, and fullscreen-suppression on Linux —
  explicitly deferred (see proposal.md).
- Wayland-specific positioning protocols (e.g. layer-shell) — out of scope;
  Linux support here is a wx-portable best effort, consistent with the
  existing "GNOME/Wayland may ignore always-on-top" note in `docs/linux.md`.
- Any refactor that unifies the Windows and Linux code paths behind a shared
  abstraction — see Decisions below.

## Decisions

**1. Add a Linux branch in the same `overlay_frame.cpp` file, not a shared
abstraction layer, and accept some duplication of the paint routine.**
Alternative considered: extract `OnPaint`/`ReprojectAndResize` into
platform-agnostic free functions shared by both branches, with only monitor
enumeration and topmost/opacity/positioning behind a small interface. This is
the "correct" long-term shape, but it means touching and re-testing the
existing Windows implementation as part of a change whose actual goal is
"add Linux support" — a real regression risk on a feature that's already
shipped and working. For this MVP, the Linux branch duplicates `OnPaint`
(rendering) and the sizing math in `ReprojectAndResize`/`AnchorToSavedCorner`
(these are short and call straight into the portable `overlay.cpp`
functions), while every Win32 API call is replaced with a portable
equivalent. A follow-up change can extract the shared parts once the Linux
path has had real usage. This is flagged in Risks below.

**2. Monitor enumeration via `wxDisplay` instead of `HMONITOR`.**
`wxDisplay` is portable and already used elsewhere in the codebase
(`ui.h` includes `<wx/display.h>`; `DashboardFrame`/`OnDisplayChanged` already
react to `wxEVT_DISPLAY_CHANGED`). Build the same `MonitorData`-shaped list
(id, monitor rect, work rect, primary flag) `SelectOverlayMonitor` /
`NearestOverlayCorner` already expect, using `wxDisplay::GetGeometry()`,
`GetClientArea()` (work area), and `IsPrimary()`. `wxDisplay::GetName()` can
be empty on some Linux setups, so the monitor "id" falls back to
`"display-<index>"` when the name is empty, keeping `SelectOverlayMonitor`'s
save/restore logic working without changes to that function.

**3. Topmost + positioning via portable wx calls, not raw X11.**
Use the `wxSTAY_ON_TOP` frame style (already set at construction, unchanged)
plus `Raise()` after settings changes and display-change events as a
best-effort nudge. Position with `Move()`/`SetSize()` instead of
`SetWindowPos`. No `HWND_TOPMOST` equivalent is required — `wxSTAY_ON_TOP`
is the portable mechanism, and the existing docs caveat about
compositor-dependent behavior already sets the right expectation.

**4. Opacity via `wxTopLevelWindow::SetTransparent()`.**
Portable, returns `bool`. If it returns `false` (no compositor / unsupported),
the overlay simply renders fully opaque instead of failing — a safe
degradation, not an error state.

**5. Skip the rounded-window-region clipping on Linux.**
Windows uses `SetWindowRgn` for true rounded window edges. `OnPaint` already
draws a rounded rectangle background inside the window regardless. Skipping
the window-shape clip on Linux means the overlay has square outer corners
with a rounded-looking fill — a cosmetic simplification, not a functional
gap — instead of pulling in an X11-specific shape-extension dependency for
a first pass.

**6. No lock/click-through UI on Linux.**
`OverlaySettings.locked` stays in the shared struct (unchanged, still used by
Windows) but the Linux `MinimalOverlayFrame` never reads it for input
handling, and the Linux tray menu / settings panel don't expose a lock
toggle. Dragging is always available on Linux in this pass.

**7. Widen `#ifdef _WIN32` to `#if defined(_WIN32) || defined(__linux__)` at
the wiring layer (`ui.h`, `app.cpp`, `tray_icon.cpp`, `settings_dialog.cpp`),
keeping a nested, narrower `#ifdef _WIN32` around the genuinely Windows-only
members/fields (hotkey status, lock checkbox, suppress-fullscreen checkbox,
`ToggleOverlayLock`, `HotkeyAvailable`/`HotkeyWarning`).** This keeps the
public wiring (`ApplyOverlaySettings`, `ToggleOverlayVisibility`, tray
show/hide item, settings Enable/Visible/Opacity/Corner fields) identical in
shape across platforms, so `app.cpp`'s call sites barely change.

## Risks / Trade-offs

- **Duplication between the Windows and Linux `OnPaint`/sizing code** →
  Mitigation: keep both bodies calling into the same portable `overlay.cpp`
  functions for all actual logic (only DC drawing calls and window
  positioning calls differ), so behavior can't drift on the parts that
  matter (row selection, countdown text, corner math). Revisit unification
  in a follow-up once the Linux path is proven.
- **`wxSTAY_ON_TOP` may be ignored by GNOME/Wayland, and `SetTransparent`
  may no-op without a compositor** → Mitigation: both degrade safely
  (overlay still visible, just not always-on-top / not translucent); this
  matches the existing documented Linux caveat, not a new one introduced by
  this change.
- **`wxDisplay::GetName()` can be empty, breaking monitor-id persistence
  across restarts** → Mitigation: index-based fallback id, and
  `SelectOverlayMonitor` already handles an unresolvable saved id by falling
  back to the primary monitor.
