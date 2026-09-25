## Why

The console dashboard (`--console`) only runs as a long-lived interactive terminal UI: it clears the screen, redraws on a timer, and waits for `q`/`r` keypresses. There is no way to fetch current usage values, print them once, and return control to the shell. This blocks scripting use cases (bash scripts, cron jobs, status bars, CI checks, piping into `jq`) where a caller just wants the current snapshot values on stdout and an exit.

## What Changes

- Add a one-shot output mode to the console entry point: fetch/refresh provider snapshots once, print them, and exit immediately (no raw terminal mode, no redraw loop, no keypress handling).
- Add an output-format flag to select `text` (human-readable, same information as the existing console cards, non-interactively rendered) or `json` (machine-readable, structured snapshot data suitable for piping to tools like `jq`).
- Preserve all existing behavior: `--console` with no additional flags keeps launching the current interactive live dashboard unchanged, and desktop/tray mode is unaffected.
- One-shot mode reuses the existing settings loading, provider construction, and refresh/snapshot logic already used by interactive console mode — no duplicate data-fetching path.
- Exit code reflects overall provider health in one-shot mode (e.g. non-zero if any enabled provider is in an error state), so scripts can branch on success/failure.

## Capabilities

### New Capabilities
- `console-scriptable-output`: One-shot, non-interactive console execution mode that prints a full snapshot of configured providers in a selectable format (text or JSON) and exits, for use from scripts and other CLI tooling.

### Modified Capabilities
(none — `console-dashboard`'s interactive requirements are unchanged; this adds a new, separate invocation mode rather than altering the existing one)

## Impact

- `src/console/console_dashboard.cpp` / `src/console/console_dashboard.h`: add flag parsing for a one-shot mode and output format, add a JSON/text single-pass renderer, add a non-interactive run path that shares snapshot-fetching with `RunConsoleDashboard`.
- `src/ui/app.cpp` (`main`): extend argument parsing so `--console` combined with the new flags routes into the one-shot path instead of (or in addition to) the interactive loop.
- No changes to desktop/tray UI, provider implementations, settings format, or cache format.
