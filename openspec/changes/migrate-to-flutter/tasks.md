## 1. Project scaffold and foundations

- [x] 1.1 Create the `flutter_app/` Flutter desktop project (Windows + Linux) with `pubspec.yaml`, analysis options and a release build configuration
- [x] 1.2 Add dependencies for tray, window/overlay management, screen enumeration, and Windows FFI, and document each in the README
- [x] 1.3 Create the layered directories (`domain`, `config`, `platform`, `providers`, `scheduler`, `presentation`, `ui`) with an empty test directory mirroring them
- [x] 1.4 Add a test harness that can read the existing `../tests/fixtures/` files read-only
- [x] 1.5 Configure `flutter analyze` and `flutter test` as the lint/test commands and record them in the project docs

## 2. Domain parity

- [x] 2.1 Port the enums and value strings (`ProviderKind`, `MetricKind`, `MetricUnit`, `MetricScope`, `Provenance`, `Availability`, `Freshness`, `Health`) with the same wire strings and unknown fallbacks
- [x] 2.2 Implement the exact decimal type (BigInt unscaled value + scale) with parse, format, add and subtract matching the reference normalization
- [x] 2.3 Port `IsDecimal` with the same regex and finite-value rule
- [x] 2.4 Port `ValidateSnapshot` with the same error order and messages (decimal, percentage range, negative resource, loaded-model unit, resource-memory unit, positive window)
- [x] 2.5 Port `AggregateMetrics` with the same compatibility checks, labels and error messages
- [x] 2.6 Port `AggregateHealth` with the same error/partial/stale/disabled precedence
- [x] 2.7 Add unit tests covering decimal arithmetic, validation and aggregation, including the reference edge cases (`42.50` → `42.5`, `100.0 - 38.2` = `61.8`, zero normalization)

## 3. Configuration and persistence

- [x] 3.1 Implement `Settings`, `OverlaySettings` and `ProviderConfig` models with reference defaults, including `schemaVersion` 1, `refreshMinutes` 5 and overlay `opacity` 78
- [x] 3.2 Implement strict settings JSON decoding and encoding with the exact field allow-lists, serialization order, 2-space indent and error messages
- [x] 3.3 Implement per-kind defaults (`DefaultsForKind`) and the first-run provider defaults with executable discovery
- [x] 3.4 Implement overlay parsing normalization (opacity clamp 50–100, margin clamp 0–96, corner fallback `top-right`, monitor length/control-character clearing)
- [x] 3.5 Implement `ValidateSettings` with all reference rules and messages
- [x] 3.6 Implement atomic writes with `.tmp`/`.bak` rotation and backup recovery for settings
- [x] 3.7 Implement the cache model, strict decoding, load downgrade (freshness stale, healthy → partial) and save filtering of invalid/metric-less snapshots
- [x] 3.8 Implement `RedactedSettingsJson` with the `<protected>` marker
- [x] 3.9 Implement data-path resolution (`AI_USAGE_DATA_DIR`, writable `data/`, per-user fallback) and the portable flag
- [x] 3.10 Add tests for JSON round trips, backup recovery, validation, clamps and redaction

## 4. Platform layer

- [x] 4.1 Define `HttpTransport`, `ProcessRunner`, `SecretStore`, `SingleInstanceSignal`, `Clock` and monitor interfaces with fake implementations for tests
- [x] 4.2 Implement the URL safety policy (`https` always, loopback `http` allow-list) and the 1 MiB limit constant
- [x] 4.3 Implement `HttpTransport` on `dart:io HttpClient` with redirects disabled, request timeouts, streaming 1 MiB cap and `AIUsageMonitor/0.1` user agent
- [x] 4.4 Implement `ProcessRunner` with stdin chunking, `standardInputCloseDelay`, timeout, cancellation and process-tree kill (`taskkill /T /F` on Windows, process group `SIGKILL` on Linux)
- [x] 4.5 Implement `ProbeVersion` and executable discovery (Windows extension search order; Linux `PATH`/path lookup)
- [x] 4.6 Implement the Windows DPAPI secret store via `win32` FFI producing `dpapi:` tokens
- [x] 4.7 Implement the Linux secret store via `secret-tool` producing `secret-service:` tokens with `session:` fallback and `PersistentAvailable`
- [x] 4.8 Implement the single-instance signal (Windows mutex + auto-reset event, Linux lock/activation files) with a Flutter-specific instance name
- [x] 4.9 Implement monitor enumeration with reference identifiers, primary detection, work areas and the fallback monitor
- [x] 4.10 Add tests for URL validation, HTTP limits/redirects, secret round trips, instance signaling and monitor selection

## 5. Provider adapters and parsers

- [x] 5.1 Implement the shared provider base behavior (base snapshot, API key retrieval, `JoinUrl`, HTTP success mapping, `Retry-After` parsing) and the HTTP error table
- [x] 5.2 Implement `NumberText` JSON-to-decimal conversion with the same string/integer/float rules
- [x] 5.3 Implement the Codex adapter: five JSONL requests, 3000 ms stdin close delay, account/rate-limit/usage parsing, labels, derived remaining, error mapping
- [x] 5.4 Implement the Claude adapter: `/usage` invocation, terminal text cleanup, percentage parsing, reset parsing and `CliBridge` metrics
- [x] 5.5 Implement the DeepSeek adapter: balance endpoint, per-currency metrics, optional derived spend and unsupported token metric
- [x] 5.6 Implement the OpenAI-compatible adapter: `/models` test, route resolution, ordered JSON Pointer mappings and the no-route placeholders
- [x] 5.7 Implement the Ollama adapter: `/api/ps` parsing, RFC 3339 unload parsing, `/api/me` account label, cloud `/api/usage` metrics and credential host separation
- [x] 5.8 Implement `TestConnection` and capabilities for every provider kind with the reference messages and details
- [x] 5.9 Add fixture tests for every provider covering success, malformed, unauthorized and idle cases, and assert field-for-field snapshot equality

## 6. Scheduler and application controller

- [x] 6.1 Implement the refresh scheduler with interval validation, max two concurrent refreshes, queued coalescing and `RefreshAll`/`RefreshOne`
- [x] 6.2 Implement the backoff algorithm with deterministic per-provider jitter, 60-minute cap and `Retry-After` override
- [x] 6.3 Implement error mapping to snapshots and failure counting/reset behavior
- [x] 6.4 Implement the `AppController` equivalents of `PublishSnapshots`, `MarkRefreshing`, stale preservation and cache writes on successful snapshots
- [x] 6.5 Implement startup ordering, cache preload, manual refresh and provider rebuild triggering
- [x] 6.6 Add tests for interval enforcement, coalescing, backoff timing, recovery reset and stale preservation

## 7. Dashboard and theming

- [x] 7.1 Implement the semantic theme (light/dark detection via luminance, contrast adjustment, spacing and radius tokens) with an environment theme override for tests
- [x] 7.2 Implement the dashboard app bar with title, refresh, settings and always-visible controls
- [x] 7.3 Implement the responsive grid (400-logical-pixel minimum cell, 12-pixel margins, multi-column growth, single column compact) preserving configuration order
- [x] 7.4 Implement provider cards with health pill, observation/freshness line, account line, metric rows, percentage progress, reset/provenance metadata and error notices, applying the reference card filtering rules
- [x] 7.5 Implement empty, no-metrics, refreshing and disabled states with equivalent Spanish text
- [x] 7.6 Implement always-on-top and close-to-tray behavior, plus the tray-unavailable fallback notice
- [x] 7.7 Add widget tests for grid column rules, card content and compact reflow

## 8. Settings interface

- [x] 8.1 Implement the settings layout with global preferences, overlay preferences and data-folder action
- [x] 8.2 Implement the provider list with add, remove and selection, plus per-kind field visibility
- [x] 8.3 Implement load/save of provider fields, credential persistence choice, forget-keys and cloud-credential clearing on kind change
- [x] 8.4 Implement connection testing with capability detail and secret redaction
- [x] 8.5 Implement save validation with the reference Spanish messages and invalid-configuration dialog
- [x] 8.6 Implement compact/stacked layout at the reference breakpoint
- [x] 8.7 Add tests for add/remove defaults, field visibility, validation rejection and save/cancel semantics

## 9. System tray

- [x] 9.1 Implement the tray icon with health-color rendering and aggregate-health updates
- [x] 9.2 Implement the tooltip composition with priority ordering, metric selection, age text, stale suffix and length cap
- [x] 9.3 Implement the tray menu with dashboard, refresh, overlay visibility/lock items when applicable, configuration and exit
- [x] 9.4 Implement left-click activation and tray-unavailable detection
- [x] 9.5 Add tests for icon health mapping, tooltip ordering/truncation and menu enablement

## 10. Minimal overlay

- [x] 10.1 Implement overlay projection: metric filtering, labels, `FormatMetric` values, status precedence, status rows and capacity/hidden-count rules
- [x] 10.2 Implement reset and unload countdown formatting and the next-countdown-boundary computation
- [x] 10.3 Implement the overlay window (frameless, topmost, skip-taskbar, buffered custom painting, rows, progress tracks and additional-count summary)
- [x] 10.4 Implement opacity normalization, hover raise to at least 95 percent and persistence
- [x] 10.5 Implement drag and nearest-corner snapping with monitor/corner persistence and DPI-aware anchoring/on-screen clamping
- [x] 10.6 Implement Windows lock/click-through styles (`WS_EX_TRANSPARENT`, `MA_NOACTIVATE`, `HTTRANSPARENT`) and the tray toggle
- [x] 10.7 Implement the Windows `Ctrl+Alt+U` global shortcut with failure warning and tray recovery
- [x] 10.8 Implement Windows event-driven full-screen suppression with foreground/location hooks
- [x] 10.9 Implement countdown scheduling limited to formatted-minute changes and no idle polling
- [x] 10.10 Implement overlay settings application from the settings window and tray, plus enable/disable teardown
- [x] 10.11 Add tests for projection, capacity, countdown text/scheduling, corner math, monitor fallback and opacity clamping

## 11. Parity verification

- [x] 11.1 Add a reference dump mode or script that emits normalized snapshots, settings/cache JSON, tooltips and overlay projections from the C++ app
- [x] 11.2 Commit the generated parity corpus under `flutter_app/test/parity/`
- [x] 11.3 Add parser fixture tests comparing Flutter output against the corpus byte-for-byte
- [x] 11.4 Add cross-application settings/cache round-trip tests in both directions
- [x] 11.5 Add tooltip, countdown, overlay projection and redacted-export parity tests
- [x] 11.6 Document the manual side-by-side comparison procedure using one shared data directory
- [x] 11.7 Run the harness and resolve any reported field, provider or input differences

## 12. Packaging and documentation

- [x] 12.1 Add Windows release build and packaged distribution output for the Flutter app
- [x] 12.2 Add Linux release build and packaged distribution output for the Flutter app
- [x] 12.3 Document build, test and parity commands in `flutter_app/README.md`
- [x] 12.4 Update the repository README to describe the two applications, their shared data contract and how to compare them
- [x] 12.5 Verify both applications build and run from a clean checkout and record the result
