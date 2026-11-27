## Why

Users who work with Google Antigravity CLI (`agy`) alongside Claude Code and Codex currently cannot monitor their Antigravity quota consumption, remaining quota, or next quota reset time inside AI Usage Monitor. Adding `agy` support on the same normalized CLI-bridge foundation as Claude and Codex lets users track all three local AI coding clients from the desktop dashboard, tray tooltip, minimal overlay, and console/JSON views.

## What Changes

- Add a new local CLI provider kind (`ProviderKind::Agy`, serialized as `"agy"`) modeled after the Claude and Codex local bridges.
- Integrate with the installed `agy` binary non-interactively via `agy -p "/usage" --output-format json` (no stdin, no pseudo-terminal, no model turn, and no private credential file reading), bounded by the shared 10-second timeout and cancellation handling.
- Normalize each reported quota bucket/pool into complementary `UsedPercent` (`CliBridge` or `ProviderReported`) and `RemainingPercent` (`Derived`) metrics with its `resetsAt` timestamp and optional account/tier metadata, matching the snapshot shape used by Codex and Claude.
- Handle unauthenticated `agy` sessions, `GEMINI_API_KEY` sessions (which have no subscription quota, exiting with status 2), and unrecognized outputs with actionable, secret-free diagnostics and preserved stale cache behavior.
- Wire `agy` into first-launch auto-discovery, portable executable reference handling, Settings UI provider type/editor/connection test, console dashboard builder, and unit/fixture tests (including a `--probe-agy-usage` developer diagnostic).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `provider-usage-monitoring`: Add non-interactive `agy` quota integration, normalized used/remaining quota windows with reset times, and explicit unauthorized/API-key/unsupported diagnostics.
- `provider-configuration`: Add `agy` to visual provider management, first-launch client discovery, portable executable configuration, and pre-save connection testing.

## Impact

- Domain, configuration, and provider engine (`include/ai_usage/domain.h`, `include/ai_usage/providers.h`, `src/domain.cpp`, `src/config.cpp`, `src/providers.cpp`).
- Desktop and console wiring (`src/ui/app.cpp`, `src/ui/settings_dialog.cpp`, `src/console/console_dashboard.cpp`).
- Unit/fixture test suite and diagnostic probe (`tests/test_main.cpp`, `tests/fixtures/`).
- No new third-party dependencies or direct Google OAuth/backend API calls from `ai-usage-monitor`; authentication stays owned by the `agy` CLI.
