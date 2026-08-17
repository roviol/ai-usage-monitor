## Why

Windows users get an always-on-top minimal overlay showing quota usage at a
glance (the equivalent of a persistent status widget near the clock). Linux
users currently have no such option: `docs/linux.md` already documents that
the tray icon may not be available on every desktop, and even when it is, the
tray only shows one line of tooltip text. The user wants the same kind of
always-visible "how much do I have left" glance on Linux, comparable to the
Windows overlay, without needing to click into the dashboard.

## What Changes

- Add a minimal, always-on-top overlay window for Linux, reusing the exact
  same visual style and quota-row projection logic (`ai_usage::overlay.h`)
  already used by the Windows overlay — same provider/label/value/reset-time
  rows, same 4-line-ish compact sizing rules.
- Scope is intentionally smaller than Windows for this first pass (MVP,
  confirmed with the user):
  - Show/hide from the tray menu, corner-anchored (top-right by default,
    matching the existing default), draggable to reposition, snaps to the
    nearest corner on release, remembers monitor + corner across restarts.
  - Configurable opacity (50–100%), with the same hover-brightens-then-fades
    behavior as Windows, reusing `wxTopLevelWindow::SetTransparent`.
  - **Not included in this pass**: click-through lock, the global
    `Ctrl+Alt+U` recovery shortcut, and automatic hiding over full-screen
    apps. Wayland has no portable API for global hotkeys or foreground-window
    detection, and GNOME/Wayland compositors may ignore "always on top"
    entirely (already noted in `docs/linux.md`); X11 generally honors it.
    These can be revisited in a follow-up change if there's demand.
- Settings dialog and tray menu gain the Linux-relevant overlay controls
  (Enable, Show/Hide, Opacity, Corner) without the Windows-only ones (lock,
  full-screen suppression, hotkey status).
- No changes to `OverlaySettings`/config schema — it's already
  platform-neutral and already round-trips through settings persistence.

## Capabilities

### New Capabilities
- `linux-minimal-overlay`: the Linux-specific minimal overlay — its scope
  (visible/hidden, opacity, corner placement, multi-monitor recovery, tray
  and settings controls, lightweight rendering) is a deliberate subset of
  `windows-minimal-overlay`, omitting click-through lock, global shortcut,
  and full-screen suppression.

### Modified Capabilities
- `windows-minimal-overlay`: the existing "Application runs outside Windows"
  scenario states overlay behavior remains entirely unavailable on
  non-Windows platforms. That's no longer accurate for Linux, which now has
  its own (smaller-scope) overlay; the scenario is updated to say so while
  leaving every Windows-specific requirement (click-through, global
  shortcut, full-screen suppression, native rendering details) unchanged.

## Impact

- **Code**: `src/ui/overlay_frame.cpp` (add a Linux branch reusing the
  Windows file's portable parts — paint routine, drag handling, corner
  snapping — with Win32 APIs replaced by portable `wxDisplay`/wx frame
  calls), `src/ui/ui.h` (widen `MinimalOverlayFrame` declaration beyond
  `_WIN32`), `src/ui/app.cpp` (widen overlay wiring guards), `src/ui/tray_icon.cpp`
  (widen tray menu guard, Linux gets Show/Hide only, no lock item),
  `src/ui/settings_dialog.cpp` (split the overlay panel into a shared subset
  plus Windows-only extras).
- **No changes** to `include/ai_usage/overlay.h` / `src/overlay.cpp` (the
  portable projection/geometry engine) or `include/ai_usage/config.h`
  (`OverlaySettings` already covers everything needed).
- **Docs**: `docs/linux.md` gains a short section describing the overlay and
  its known Wayland/GNOME "always on top" caveat (already partially noted).
