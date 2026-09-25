## Context

See proposal.md - Why. The desktop dashboard (`src/ui/dashboard.cpp`) is a wxWidgets `wxFrame` that reads `ProviderSnapshot` data produced by the platform-independent core: `src/config.cpp` (settings), `src/providers.cpp` (polling), `src/scheduler.cpp` (refresh cadence), `src/domain.cpp` (data model), and `src/presentation.cpp` / `src/overlay.cpp` (label/countdown formatting shared by the tray tooltip and the overlay). None of that core code depends on wxWidgets. `src/ui/app.cpp` owns process bootstrap: settings load, single-instance signaling, scheduler wiring, and handing snapshots to the dashboard/tray. The console mode needs its own thin presentation layer that consumes the same `ProviderSnapshot`/`Metric` types and the same `FormatResetMetadata`/`FormatResetCountdown` helpers, without touching `src/ui/*`.

## Goals / Non-Goals

**Goals:**
- Reuse `config.cpp`, `providers.cpp`, `scheduler.cpp`, `domain.cpp`, `presentation.cpp`, `overlay.cpp` byte-for-byte (no forked copies) for the console mode.
- Render one section per provider with health, metrics, progress bars, provenance, and reset countdowns matching the desktop dashboard's content.
- Redraw automatically on the scheduler's cadence and support a manual refresh keypress and a quit keypress.
- Ship as a Linux-only build target, since the proposal restricts scope to Linux.

**Non-Goals:**
- No mouse support, scrolling history, or multi-window terminal layout — a single full-screen view is sufficient.
- No Windows/macOS terminal support in this change.
- No changes to `Settings` schema, provider polling behavior, or the wxWidgets dashboard/tray.
- No always-on-top equivalent or settings dialog in console mode; settings continue to be edited via the existing desktop settings dialog or by hand-editing the settings file.

## Decisions

- **Rendering approach: plain ANSI redraw via a small custom renderer, not a full TUI library.** The dashboard's needs (labeled text lines, a simple `[####----]` progress bar, periodic full-screen redraw) don't need widget layout, focus management, or mouse handling. Alternatives considered: ncurses (adds a native dependency and cross-compilation complexity for a single feature) and FTXUI (nicer widgets but another third-party dependency to vendor/build). A small internal module using ANSI escape codes (clear screen, cursor home, SGR colors) keeps the dependency surface at zero and matches the project's existing pattern of hand-rolled presentation helpers (`presentation.cpp`, `overlay.cpp`).
- **New entry point via a CLI flag on the existing binary, not a separate executable.** `--console` (or similar) on the current binary reuses `src/ui/app.cpp`'s existing settings/scheduler bootstrap instead of duplicating it in a second `main()`. On Linux, when the flag is present, the process skips wxWidgets app initialization (`wxApp::OnInit`, tray, GUI dashboard) entirely and runs a console loop instead, avoiding any GTK/X11 requirement for headless use. Alternative considered: a fully separate `ai-usage-monitor-console` binary — rejected because it would duplicate settings loading, single-instance signaling, and scheduler wiring that already lives in `app.cpp`.
- **Terminal input handling: raw-mode single-key reads on a background thread (or via `select`/`poll` on stdin) feeding the same refresh/quit intents the desktop dashboard's toolbar buttons trigger.** This keeps the scheduler and provider polling code untouched — the console layer only calls the same "refresh now" and "shut down" entry points already used by `app.cpp`.
- **Progress bar and countdown text reuse `presentation.cpp`/`overlay.cpp` formatting functions directly** (`FormatResetMetadata`, `FormatResetCountdown`, `FormatUnloadCountdown`) rather than reimplementing countdown/timezone logic, to guarantee identical wording to the desktop dashboard and tray tooltip.

## Risks / Trade-offs

- [Terminal resize while rendering could misalign the layout] → Recompute layout dimensions from the terminal size at the start of each redraw cycle rather than caching a fixed width.
- [ANSI escape codes may not render correctly in all terminal emulators] → Target standard ANSI/VT100 sequences supported by common Linux terminals (xterm, gnome-terminal, tmux, screen); no dependency on a specific terminal's extended features.
- [Running both console and desktop modes against the same settings/data directory concurrently could race on singleton-instance signaling] → Reuse the existing single-instance guard from `app.cpp` unchanged so console mode participates in the same lock.
- [Hand-rolled ANSI rendering may need incremental hardening for edge cases (very narrow terminals, non-UTF8 locales)] → Acceptable initial trade-off; console mode targets typical terminal widths and can be hardened later without spec changes.
