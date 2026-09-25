## 1. CLI flag parsing

- [x] 1.1 In `src/ui/app.cpp`, extend argument parsing so `--once` and `--format <text|json>` are recognized alongside `--console` and passed through to the console entry point.
- [x] 1.2 In `src/console/console_dashboard.cpp`/`.h`, parse `--once` and `--format` from `argv` inside (or before) `RunConsoleDashboard`, defaulting format to `text`; reject an unsupported format value with a clear stderr message and non-zero exit before doing any provider work.

## 2. Shared snapshot fetch

- [x] 2.1 Extract the setup currently inline in `RunConsoleDashboard` (paths, single-instance check, settings load, provider construction, cache load) into a reusable function shared by both interactive and one-shot paths.
- [x] 2.2 Add a blocking "refresh all enabled providers and wait until each has reported (or a bounded timeout elapses)" helper, using the existing `RefreshScheduler` callback plus a condition variable/counter; providers that time out fall back to their last cached snapshot the same way the interactive loop already does for "no data yet".
- [x] 2.3 Build the ordered `vector<ProviderSnapshot>` (in configured-provider order) from the fetch result, reusing the same ordering logic currently inline in the interactive loop.

## 3. Text and JSON rendering for one-shot mode

- [x] 3.1 Add a one-shot text renderer that reuses `RenderProviderSection` per provider (no ANSI screen-clear, no footer key hints) and prints to stdout.
- [x] 3.2 Add `SnapshotsToJson(const std::vector<ProviderSnapshot>&)` producing one JSON array with the fields specified in design.md (`providerId`, `displayName`, `kind`, `health`, `freshness`, `observedAt`, `accountLabel`, `metrics[]`, `error`), using the project's existing JSON library.
- [x] 3.3 Ensure JSON output is the only content written to stdout in JSON mode (warnings/errors go to stderr).

## 4. One-shot execution path and exit code

- [x] 4.1 Implement the one-shot run path: setup → blocking fetch → render (text or json) → exit, with no raw terminal mode, no signal handler installation, and no loop.
- [x] 4.2 Compute the process exit code from provider health: non-zero if any enabled provider ends in `Health::Error`, zero otherwise.
- [x] 4.3 Persist cache after one-shot fetch the same way interactive mode does on exit (`SaveCache`), so subsequent runs (one-shot or interactive) see fresh cached data.

## 5. Verification

- [x] 5.1 Manually run `--console --once --format text` and `--console --once --format json` against a configured settings file; confirm output matches spec scenarios and process exits without hanging.
- [x] 5.2 Verify `--console` alone still launches the unchanged interactive dashboard (regression check).
- [x] 5.3 Pipe JSON output through `jq` to confirm it parses as valid, well-formed JSON with no stray text on stdout.
- [x] 5.4 Verify exit code is non-zero when a provider is forced into an error state (e.g. invalid credentials) and zero when all providers are healthy.
