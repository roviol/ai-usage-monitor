## 1. Project and build foundation

- [x] 1.1 Create the C++20 source, include, test, asset and packaging directory structure with warning-as-error conventions.
- [x] 1.2 Add CMake presets for Windows Debug/Release and Linux Debug/Release, including a documented full-path/Developer PowerShell workflow for the verified Visual Studio installation.
- [x] 1.3 Pin wxWidgets and the selected small JSON dependency to exact releases and checksums, with an offline dependency-cache option.
- [x] 1.4 Build a minimal wxWidgets GUI target with MSVC `/MT`, Unicode and `WINDOWS` subsystem and verify that the Release artifact opens no console.
- [x] 1.5 Add unit-test and fixture-test targets plus CI jobs that configure, build and run tests on Windows and Linux.

## 2. Domain model and persistence

- [x] 2.1 Implement provider, metric, unit, scope, provenance, availability, freshness and error value types without UI dependencies.
- [x] 2.2 Implement snapshot validation and aggregation rules that reject invalid numeric data and prevent totals across incompatible units or scopes.
- [x] 2.3 Add unit tests for partial coverage, derived metrics, stale snapshots and aggregate status precedence.
- [x] 2.4 Define version-1 settings and cache schemas with strict JSON decoding, defaults and redacted diagnostic serialization.
- [x] 2.5 Implement atomic settings/cache writes, backup recovery and portable-folder versus per-user data-directory selection with tests for interrupted writes.

## 3. Platform services and security

- [x] 3.1 Define injectable interfaces for HTTP, hidden child processes, clocks, secret storage, filesystem locations and single-instance signaling.
- [x] 3.2 Implement the Windows hidden-process runner with redirected pipes, cancellation, timeout, process-tree cleanup and no visible console.
- [x] 3.3 Implement the Windows WinHTTP client with system TLS, 10-second timeout, 1 MiB response cap, safe redirect policy, `Retry-After` capture and secret-redacted errors.
- [x] 3.4 Implement Windows DPAPI current-user secret storage and tests proving settings/cache/log output never contains plaintext keys.
- [x] 3.5 Implement Windows single-instance activation so a second launch focuses the resident dashboard and exits.
- [x] 3.6 Add executable discovery and version probing for Codex and Claude without starting login or reading client authentication files.

## 4. Provider adapters

- [x] 4.1 Implement a JSONL/JSON-RPC client for an ephemeral `codex app-server` process, including initialize, request correlation, protocol errors and clean shutdown.
- [x] 4.2 Implement the Codex adapter for `account/read`, `account/rateLimits/read` and `account/usage/read` with fixtures for multiple windows, partial fields, API-key-only auth and authentication failure.
- [x] 4.3 Implement the DeepSeek preset and `/user/balance` parser with multi-currency fixtures, decimal-safe values and optional derived-budget calculation.
- [x] 4.4 Implement the bounded generic OpenAI-compatible adapter for `/models`, explicit metric routes and JSON Pointer mappings with schema and origin validation.
- [x] 4.5 Implement Claude subscription usage exclusively through a hidden, non-interactive `claude /usage` child process without a direct Anthropic API adapter.
- [x] 4.6 Run and document a non-consuming spike against Claude Code 2.1.221 and capture only secret-free `/usage` output fixtures.
- [x] 4.7 Implement fail-closed plain-text parsing for recognized `claude /usage` session and weekly percentage lines, with timeout and fixture tests.
- [x] 4.8 Implement the provider factory, capability reporting and non-destructive connection tests for every provider type.

## 5. Refresh orchestration

- [x] 5.1 Implement the event-driven scheduler with 5-minute default, validated 1-to-60-minute setting and no polling between due times.
- [x] 5.2 Implement per-provider coalescing, maximum concurrency of two, cancellation and independent result delivery.
- [x] 5.3 Implement bounded exponential backoff with jitter, `Retry-After` handling and one-attempt manual refresh semantics.
- [x] 5.4 Integrate atomic last-good cache loading so startup data is stale until confirmed and current errors coexist with cached metrics.
- [x] 5.5 Add deterministic scheduler tests with a fake clock for normal cadence, timeout, rate limiting, coalescing and manual refresh.

## 6. Windows tray and dashboard

- [x] 6.1 Create application lifecycle wiring that starts resident with the dashboard hidden and shuts down timers and child processes only through explicit exit.
- [x] 6.2 Add status icon assets for healthy, partial/stale, error/auth and no-data states and implement aggregate icon selection.
- [x] 6.3 Implement the deterministic 127-character Windows tooltip composer with freshness and priority tests.
- [x] 6.4 Implement tray click and context-menu actions for dashboard, refresh all, settings and exit, including taskbar recreation after Explorer restarts.
- [x] 6.5 Build the single dashboard window with responsive provider cards, supported and unavailable metrics, reset times, provenance, stale data and actionable errors.
- [x] 6.6 Add one non-blocking refresh-all control in the top toolbar with independent provider progress and completion feedback.
- [x] 6.7 Implement the persistent `Siempre visible` toggle, default-off behavior and immediate Windows top-most update.
- [x] 6.8 Implement keyboard navigation, readable scaling/high-DPI behavior and accessible labels for icon-only status or actions.

## 7. Visual configuration workflow

- [x] 7.1 Build provider list management for add, edit, enable, disable and remove actions, including first-run review of detected clients.
- [x] 7.2 Build provider-specific forms for Codex/Claude executables, DeepSeek and generic OpenAI-compatible endpoints.
- [x] 7.3 Add inline validation for refresh interval, executable compatibility, URLs, loopback-only HTTP exception, JSON Pointers and optional budgets.
- [x] 7.4 Add asynchronous connection-test results with capability summary and fully redacted diagnostics.
- [x] 7.5 Add secure key save/session-only choices, undecryptable-key recovery and active data-directory display/open action.
- [x] 7.6 Add UI integration tests for saving settings, disabling a provider, invalid inputs and restoring always-on-top.

## 8. Linux target

- [x] 8.1 Provision a Linux CI build environment with wxGTK, compiler, AppImage tooling and documented GNOME/AppIndicator and KDE test images.
- [x] 8.2 Implement Linux process, HTTP/libcurl, data-directory and single-instance platform services against the shared interfaces.
- [x] 8.3 Implement Linux Secret Service storage with an explicit session-only fallback when no secure service is available.
- [x] 8.4 Integrate wxWidgets tray support and detect missing StatusNotifier/AppIndicator hosts, falling back to a normal dashboard with explanation.
- [ ] 8.5 Package the x86_64 AppImage and run Linux smoke tests for tray, dashboard, configuration and always-on-top on the selected desktops.

## 9. Verification and release

- [ ] 9.1 Add end-to-end tests with fake Codex, Claude, DeepSeek and generic HTTP/process fixtures covering healthy, partial, unauthorized, stale and schema-change states.
- [ ] 9.2 Add security tests for TLS enforcement, cross-origin redirects, response-size limits, malformed JSON/JSONL, child-process cleanup and secret redaction.
- [ ] 9.3 Create Windows measurement scripts and CI/release gates for 15 MiB size, 35 MiB idle working set, 0.2% idle CPU, 750 ms tray startup and zero between-refresh traffic.
- [ ] 9.4 Create Linux measurement scripts and release gates for 45 MiB AppImage size and 50 MiB idle RSS.
- [ ] 9.5 Produce the portable Windows x64 Release executable and verify it on a clean Windows 10/11 user session without language runtimes or VC++ Redistributable.
- [ ] 9.6 Write user documentation for first run, provider coverage, secure credential behavior, refresh/backoff, always-on-top, Linux tray limitations and complete portable removal.
- [ ] 9.7 Record third-party licenses, choose the final project name/icon/license and publish checksums for Windows and Linux artifacts.
