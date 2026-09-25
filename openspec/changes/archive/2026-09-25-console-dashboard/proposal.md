## Why

The monitor currently only ships a wxWidgets tray dashboard, which requires a graphical desktop session. On headless or terminal-first Linux setups (servers, SSH sessions, minimal window managers) users have no way to see provider usage, quotas, or reset countdowns. A text-mode dashboard that reuses the existing configuration, providers, and scheduler gives those users the same at-a-glance visibility without any GUI dependency.

## What Changes

- Add a console/text-mode dashboard entry point for Linux that renders the same information as the desktop dashboard (provider cards, health/status, usage percentages with progress bars, reset times/countdowns, provenance, and error/stale states) using a terminal UI instead of wxWidgets.
- Reuse the existing `Settings`/config loading, provider polling, and scheduler code paths unchanged — the console mode is a new presentation layer only, not a new configuration or provider system.
- Provide a full-screen, auto-refreshing terminal layout with a manual refresh key and a quit key; no tray icon, no system notifications, and no GUI window are created in this mode.
- Add a way to launch the app in console mode (e.g. a command-line flag or a separate console executable) distinct from the existing tray-resident desktop mode.
- Out of scope: Windows/macOS console support, tray icon behavior changes, and any change to provider polling logic or settings schema.

## Capabilities

### New Capabilities
- `console-dashboard`: A terminal-based, text-only rendering of provider usage cards (status, metrics, progress bars, reset countdowns) for Linux, driven by the same configuration and scheduler as the desktop dashboard, with no tray icon or GUI dependency.

### Modified Capabilities
(none — `tray-dashboard` and `responsive-dashboard-grid` remain unchanged; console mode is an additive, independent presentation.)

## Impact

- Affected code: new console UI module(s) under `src/` (e.g. `src/console/`), a new or extended app entry point to select console vs. tray mode on Linux, and `CMakeLists.txt` to build the new target/source files.
- Reused unchanged: `src/config.cpp`, `src/providers.cpp`, `src/scheduler.cpp`, `src/domain.cpp`, `src/presentation.cpp`, `src/overlay.cpp`, `src/tooltip.cpp`.
- Not affected: `src/ui/*` (wxWidgets dashboard/tray), Windows platform code.
- New dependency: a terminal-rendering approach (plain ANSI/text redraw, or a lightweight TUI library) — to be decided in design.md.
