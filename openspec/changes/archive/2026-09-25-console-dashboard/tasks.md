## 1. Console rendering module

- [x] 1.1 Create `src/console/` module (e.g. `console_dashboard.cpp`/`.h`) with a renderer that takes a list of `ProviderSnapshot` and terminal dimensions and produces text output.
- [x] 1.2 Implement provider section rendering: name, health/status marker, observation time and freshness, metrics, provenance labels — mirroring `ProviderCard` content from `src/ui/dashboard.cpp` but as plain text.
- [x] 1.3 Implement a text progress bar helper for used-percentage metrics (e.g. `[#####-----] 50%`), omitting the remaining-percentage figure.
- [x] 1.4 Reuse `FormatResetMetadata`/`FormatResetCountdown`/`FormatUnloadCountdown` from `presentation.cpp`/`overlay.cpp` for reset time and countdown text so wording matches the desktop dashboard.
- [x] 1.5 Implement error/stale rendering that shows the error message alongside cached metrics without discarding them.
- [x] 1.6 Implement ANSI screen clear/cursor-home redraw cycle that recomputes layout from current terminal size each frame.

## 2. Terminal input and lifecycle

- [x] 2.1 Implement raw-mode (or `poll`/`select`-based) stdin key reading for a manual refresh key and a quit key.
- [x] 2.2 Wire the manual refresh key to trigger an immediate poll of all enabled providers via the existing scheduler/provider entry points used by `app.cpp`.
- [x] 2.3 Wire the quit key to cancel in-flight operations within their timeout, flush persisted state, and terminate the process cleanly (no orphaned child processes).
- [x] 2.4 Restore terminal mode (echo/canonical mode) on exit, including on signal-driven termination (e.g. SIGINT/SIGTERM).

## 3. Entry point wiring

- [x] 3.1 Add a console-mode launch flag (e.g. `--console`) parsed before wxWidgets app initialization on Linux.
- [x] 3.2 When the flag is present, skip `wxApp`/tray/GUI initialization entirely and instead reuse the existing settings load, single-instance guard, and scheduler wiring from `src/ui/app.cpp` to drive the console renderer.
- [x] 3.3 Ensure console mode participates in the same single-instance signaling as desktop mode so both modes cannot run concurrently against the same data directory.

## 4. Build integration

- [x] 4.1 Add new console module source files to `CMakeLists.txt`, scoped to the Linux build.
- [x] 4.2 Verify the console mode builds and links without pulling in wxWidgets/GTK symbols beyond what the shared core already requires.

## 5. Verification

- [x] 5.1 Manually test console mode against fixture/live provider data on Linux: healthy, stale/error, partial-metric, and no-data provider states render correctly.
- [x] 5.2 Manually verify progress bars, reset countdowns (upcoming and elapsed), and provenance labels match the desktop dashboard's wording and values.
- [x] 5.3 Manually verify manual refresh and quit keys work, and that quitting leaves no orphaned process.
- [x] 5.4 Manually verify terminal resize during a redraw does not corrupt the layout.
