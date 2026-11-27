## 1. Live Schema Probe and Fixtures

- [x] 1.1 Add a `--probe-agy-usage` developer probe (mirroring `--probe-codex-usage` and `--probe-claude-usage`) and run `agy -p "/usage" --output-format json` on an authenticated host to verify the exact JSON payload, quota bucket names, percentage fields, and `reset_time` format.
- [x] 1.2 Add redacted fixture files in `tests/fixtures/` covering authenticated `agy` quota output, unauthenticated output, and `GEMINI_API_KEY` output.

## 2. Domain, Config, and Provider Bridge

- [x] 2.1 Add `ProviderKind::Agy` (`"agy"`) in `include/ai_usage/domain.h`, `src/domain.cpp`, and `src/config.cpp` (`ParseProviderKind` and `DefaultsForKind`).
- [x] 2.2 Refactor the RFC 3339 timestamp parser in `src/providers.cpp` into a shared helper reused by Ollama unload times and `agy` `reset_time` values, and declare `ParseAgyUsageJson` in `include/ai_usage/providers.h`.
- [x] 2.3 Implement `ParseAgyUsageJson` and `AgyProvider` in `src/providers.cpp` (invoking `agy -p "/usage" --output-format json` with closed stdin, 10-second timeout, cancellation probe, complementary `UsedPercent` and `RemainingPercent` metrics with `resetsAt` per bucket, and secret-free `unauthorized` / `unsupported` error classification) and register it in `CreateProvider`.

## 3. Discovery, Settings UI, and Console Integration

- [x] 3.1 Add `"agy"` to `DefaultExecutableCommand` in `src/ui/app.cpp` and `src/console/console_dashboard.cpp`, and include `DiscoverExecutable("agy")` in `MonitorApp::EnsureDefaults`.
- [x] 3.2 Add `agy` to `src/ui/settings_dialog.cpp` (`KindLabels`, `KindFromIndex`, `IndexFromKind`, `UpdateFieldVisibility`, `OnAdd`, `OnAccept`) so users can add, edit, validate, and test `agy` providers using the local-client fields.

## 4. Verification

- [x] 4.1 Add unit and fixture tests in `tests/test_main.cpp` for `ParseAgyUsageJson`, `AgyProvider` (healthy capture, unauthenticated state, `GEMINI_API_KEY` exit code 2, malformed JSON, timeout/cancellation, secret redaction), settings/cache round-tripping, and overlay/tooltip/reset presentation.
- [x] 4.2 Build the project and pass `ctest` (`ai-usage-unit-tests` and `ai-usage-fixture-tests`), then verify real capture with `--probe-agy-usage`.
