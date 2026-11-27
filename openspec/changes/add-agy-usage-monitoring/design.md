## Context

See `proposal.md` for motivation and scope.

AI Usage Monitor already implements two local CLI-bridge providers in `src/providers.cpp`:
- `CodexProvider`, which communicates over stdio JSON-RPC with `codex app-server` and emits `UsedPercent` (`ProviderReported`) + `RemainingPercent` (`Derived`) metrics with `resetsAt` timestamps per quota window.
- `ClaudeSubscriptionProvider`, which checks `claude auth status --json` and executes `claude /usage` non-interactively with redirected output, closed stdin, and a 10-second deadline, emitting `UsedPercent` (`CliBridge`) + `RemainingPercent` (`Derived`) metrics with `resetsAt` timestamps.

Downstream layers (`ProviderCard` in `src/ui/dashboard.cpp`, `src/console/console_dashboard.cpp`, `src/overlay.cpp`, `src/tooltip.cpp`, and `FormatResetMetadata` in `src/presentation.cpp`) already consume normalized `ProviderSnapshot` objects generically: they render progress bars for `UsedPercent`, display local-timezone reset timestamps and countdowns (`Reinicia YYYY-MM-DD HH:MM:SS · reinicia en ...`), keep complementary `RemainingPercent` metrics in snapshots and `--format json` output, and preserve stale cached metrics on error.

## Goals / Non-Goals

**Goals:**
- Reuse the normalized snapshot model (`UsedPercent` + complementary `RemainingPercent` + `resetsAt` per quota pool/bucket) so `agy` behaves identically to Claude and Codex across the dashboard, console, JSON CLI output, tray tooltip, and minimal overlay.
- Keep quota collection strictly local and non-interactive via the installed `agy` CLI without triggering a model turn or reading Google OAuth tokens.
- Provide clear, actionable, secret-free Spanish diagnostics for unauthenticated sessions, `GEMINI_API_KEY` mode, timeouts, and schema changes.
- Support auto-discovery on first run, portable executable paths, Settings UI configuration, and connection testing.

**Non-Goals:**
- Reading private OAuth credentials from `~/.gemini/` or OS keychains, or calling `cloudcode-pa.googleapis.com` directly.
- Running an interactive PTY/TUI session or invoking a conversational prompt to inspect quota.
- Implementing `/credits` billing or OAuth login automation from inside AI Usage Monitor.

## Decisions

1. **Non-interactive bridge via `agy -p "/usage" --output-format json`**:
   - Antigravity CLI supports read-only slash commands in print mode (`-p "/usage"`) without starting an agent turn, spending quota, or creating a conversation, and emits structured JSON with UTC `reset_time` timestamps under `--output-format json`.
   - *Alternatives considered*:
     - Direct HTTP requests using `agy`'s OAuth credentials → Rejected to preserve the project's credential isolation boundary.
     - `agy acp` stdio server → ACP exposes session/model configuration rather than user quota/reset reporting.
     - Scraping plain-text or TUI `/usage` → More brittle than `--output-format json` and relies on local timezone formatting.

2. **Schema verification with `--probe-agy-usage` and defensive normalization**:
   - Inspection of the installed `agy` binary (1.5.18) shows quota fields (`used_percentage`, `remaining_percentage`, `remaining_fraction`, `reset_time`, `quota_buckets`/`buckets`) and exit code `2` when connected with `GEMINI_API_KEY`. Because the sandboxed planning environment cannot execute authenticated network requests, the exact outer JSON envelope must be confirmed with a real `--probe-agy-usage` run during implementation.
   - `ParseAgyUsageJson` will compute/normalize both `UsedPercent` and `RemainingPercent` (deriving the missing side via `SubtractDecimals("100", ...)` when only one side is present) and clamp/validate `0..100` percentages so snapshots always satisfy `ValidateSnapshot` and parity with Claude/Codex.
   - Extract a shared RFC 3339 UTC/offset timestamp parser helper from the existing `ParseOllamaUnloadTime` logic in `src/providers.cpp` so `agy` `reset_time` values and Ollama timestamps share one tested parser without `std::chrono::parse` (preserving Ubuntu/GCC compatibility).

3. **Closed-stdin subprocess execution and error classification**:
   - Execute `agy` with empty `standardInput` and immediate EOF (`standardInputCloseDelay == 0`), a 10-second timeout, and cancellation probing. When unauthenticated, `agy` prints an OAuth prompt and waits on stdin; immediate EOF prevents hanging.
   - Classify outputs into typed `ProviderError` values without echoing raw stdout/stderr:
     - Unauthenticated / `UNAUTHENTICATED` / login prompt → `"unauthorized"` (non-transient), instructing the user to authenticate in `agy`.
     - Exit code `2` or `GEMINI_API_KEY` notice → `"unsupported"` (non-transient), explaining that API-key mode has no account quota.
     - Unrecognized or malformed JSON → `"unsupported"` / parse error without guessing metrics.

4. **Configuration, UI, and discovery parity**:
   - Add `ProviderKind::Agy` (`"agy"`) across `domain.h`, `domain.cpp`, `config.cpp`, `providers.cpp`, `settings_dialog.cpp`, `app.cpp`, and `console_dashboard.cpp`.
   - Include `DiscoverExecutable("agy")` in `EnsureDefaults()` and `DefaultExecutableCommand()` so existing first-run discovery and portable executable references work identically to `"codex"` and `"claude"`.

## Risks / Trade-offs

- **Live JSON shape uncertainty until authenticated probe** → Run `--probe-agy-usage` during `/opsx-apply`, save a redacted fixture in `tests/fixtures/`, and finalize `ParseAgyUsageJson` against observed output rather than assumptions.
- **Language-server startup latency inside `agy`** → Cold invocation of `agy -p "/usage"` starts its internal server; enforce the existing 10-second timeout and rely on `MonitorApp`/`RefreshScheduler` stale-cache retention if a run times out.
- **Unauthenticated stdin hang** → Ensure `IProcessRunner` closes child stdin immediately when `standardInput` is empty so `agy` exits cleanly instead of waiting 60 seconds for an auth code.
