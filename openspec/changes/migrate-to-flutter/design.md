## Context

See `proposal.md` — Why. The current application is a C++20/wxWidgets desktop app with a hand-written platform layer (`IHttpClient`, `IProcessRunner`, `ISecretStore`, `ISingleInstanceSignal`, `IClock`) and pure-domain modules (`domain.cpp`, `config.cpp`, `providers.cpp`, `scheduler.cpp`, `overlay.cpp`, `tooltip.cpp`). Provider parsing, decimal arithmetic, scheduling and overlay projection are already framework-independent and are the contract the Flutter app must reproduce.

Constraints that shape the approach:
- Behavior parity is the acceptance criterion; visual styling may differ.
- `settings.json` and `cache.json` are the shared contract, including protected credential tokens (`dpapi:…`, `secret-service:…`, `session:…`).
- Windows has overlay-specific native behavior (click-through, no-activate, full-screen suppression, `Ctrl+Alt+U`); Linux does not.
- Both applications must run at the same time for comparison.

## Goals / Non-Goals

**Goals:**
- A Flutter desktop app under `flutter_app/` whose provider output, scheduling, persistence, status text and overlay projection are field-for-field identical to the C++ app.
- Read/write compatibility with existing `settings.json`/`cache.json`, including credentials protected by the OS store.
- A deterministic test suite driven by the existing `tests/fixtures/` and by expected outputs generated from the reference.
- Both apps runnable side by side against one data directory.

**Non-Goals:**
- Retiring or modifying the C++ app in this change.
- Matching the reference's package-size, startup, idle-memory or idle-CPU release gates; Flutter's runtime footprint is larger and those gates are explicitly not parity criteria here.
- Pixel-identical UI, native widget rendering, or identical fonts/colors.
- Adding new providers or features not present in the reference.
- Mobile/web/macOS targets.

## Decisions

### 1. Separate Flutter package, layered like the C++ core
`flutter_app/` is a standard Flutter desktop project. Internal structure mirrors the C++ layering so parity can be tested per layer:

- `lib/domain/` — enums, `Metric`, `ProviderSnapshot`, decimal string arithmetic, snapshot validation, metric and health aggregation. Pure Dart, no Flutter imports.
- `lib/config/` — settings/cache models, JSON codec, validation, atomic writes with `.bak`, data-path resolution, redacted export. Pure Dart.
- `lib/platform/` — interfaces `HttpTransport`, `ProcessRunner`, `SecretStore`, `SingleInstanceSignal`, `Clock`, `MonitorService`, plus real and fake implementations.
- `lib/providers/` — one adapter per kind plus the parser functions.
- `lib/scheduler/` — refresh scheduler with the reference backoff.
- `lib/presentation/` — metric/health/freshness/provenance/age formatting and overlay projection. Pure Dart.
- `lib/ui/` — Flutter widgets: dashboard, settings, tray, overlay.
- `lib/app_controller.dart` — orchestration equivalent to `MonitorApp`/`PublishSnapshots`.

*Alternatives considered:* a single flat package (fast to start, but parity tests become entangled with widgets) and a shared Dart package reused by a future CLI (unnecessary now).

### 2. Exact string decimal arithmetic
Port the reference's sign/scale digit-string arithmetic to Dart as an exact decimal type (BigInt unscaled value + scale, normalized by stripping trailing zeros and collapsing zero). Derived values (`100 - used`, budget spend, aggregations) must produce the same strings as the reference (for example `42.50` → `42.5`, `100.0 - 38.2 = 61.8`). Do not use `double` for any persisted or displayed value.

*Alternatives considered:* `decimal` package (adds a dependency and may normalize differently) and `double` (loses exactness and breaks parity).

### 3. HTTP via `dart:io HttpClient` behind an interface
Use `dart:io`'s `HttpClient` directly with `followRedirects = false`, `connectionTimeout`/`idleTimeout` equal to the request timeout, a streaming read that aborts past 1 MiB, `User-Agent: AIUsageMonitor/0.1`, and the shared `IsSafeEndpointUrl` gate before every send. `package:http` is avoided because its redirect and buffering behavior would need the same overrides with less control.

### 4. Process execution via `dart:io Process`, tree-killed
`Process.start` with explicit argument lists (no shell), writing stdin in chunks and closing it after `standardInputCloseDelay` (3000 ms for Codex, 0 otherwise), enforcing the request timeout and cancellation. On Windows, kill the process tree with `taskkill /PID <pid> /T /F`; on Linux, start the child in its own process group and `kill(-pid, SIGKILL)`. `ProbeVersion` runs `<exe> --version` with a 5-second timeout and returns trimmed stdout, else stderr, else empty.

### 5. Credentials via OS-native FFI, not a keyed plugin
Cross-application credential interop requires the same on-disk token bytes. Therefore:
- Windows: `win32` FFI calling `CryptProtectData`/`CryptUnprotectData` with description `AI Usage Monitor` and `CRYPTPROTECT_UI_FORBIDDEN`, base64 (`NOCRLF`) encoded, prefixed `dpapi:`.
- Linux: run `secret-tool store/lookup` with the same `service ai-usage-monitor` attributes and the same 32-hex ids, prefixed `secret-service:`; fall back to an in-memory `session:` map when `secret-tool` is absent.
- `PersistentAvailable()` mirrors the reference (Windows always true; Linux true only when `secret-tool` is on `PATH`).

`flutter_secure_storage` is rejected because it stores values in its own backend rather than emitting the reference's `dpapi:`/`secret-service:` tokens, which would break shared settings files and cross-app reads.

### 6. Desktop integration plugins plus targeted `win32` FFI
- Tray: `tray_manager` (Windows/Linux) with a health-colored icon drawn at runtime.
- Overlay window: `window_manager` for frameless, always-on-top, skip-taskbar and opacity, plus `win32` FFI for the behaviors no plugin exposes: `WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW|WS_EX_LAYERED|WS_EX_TRANSPARENT` styles, `WM_MOUSEACTIVATE → MA_NOACTIVATE`, `WM_NCHITTEST → HTTRANSPARENT` when locked, `SetWinEventHook` for `EVENT_SYSTEM_FOREGROUND`/`EVENT_OBJECT_LOCATIONCHANGE` full-screen suppression, `WM_DPICHANGED` handling, a rounded window region, and `RegisterHotKey(MOD_CONTROL|MOD_ALT|MOD_NOREPEAT, 'U')`.
- Single instance: `win32` named mutex + auto-reset event on Windows; lock file plus a polled activation file on Linux, using a **Flutter-specific instance name** so both apps can run concurrently.
- Monitors: `screen_retriever`/`win32` enumeration producing the same identifiers (`\\.\DISPLAYn` on Windows, display name or `display-N` on Linux) so persisted monitor ids survive.

*Alternatives considered:* `flutter_acrylic`/`bitsdojo_window` for window chrome (less control over click-through and no-activate) and a native plugin per platform (more code, duplicated behavior).

### 7. State management with a plain controller
A single `AppController extends ChangeNotifier` holds settings, ordered snapshots, overlay state and scheduler callbacks; widgets listen via `AnimatedBuilder`/`ValueListenableBuilder`. `provider` is the only optional convenience. This keeps ordering and lifecycle easy to reason about and test headlessly.

*Alternatives considered:* Riverpod and Bloc (more ceremony than this single-window app needs).

### 8. Parity verification from shared fixtures
- Copy or reference `tests/fixtures/*` (read-only) from Dart tests and assert normalized snapshot output.
- Generate expected `settings.json`, `cache.json`, tooltip and overlay-projection outputs from the reference via a small dump mode/script, commit them under `flutter_app/test/parity/`, and compare byte-for-byte in Dart tests.
- Keep a documented manual side-by-side procedure (same data dir, same providers) as the final acceptance check.

## Risks / Trade-offs

- [Flutter package size/startup exceed the reference's "ultra liviano" gates] → Explicit non-goal; if resource gates ever matter, revisit with a lighter runtime or keep the C++ app as the shipping binary.
- [Process tree kill differs on Windows] → Use `taskkill /T /F` and verify with the Codex app-server timeout test; accept different exit codes where the reference's Job Object codes differ.
- [Native overlay parity gaps: no-activate, click-through, Alt+Tab absence] → Assert `WS_EX_NOACTIVATE`/`WS_EX_TOOLWINDOW`/`WS_EX_TRANSPARENT` and `skipTaskbar`, and cover with manual checks plus `win32` window-style assertions.
- [Both apps writing the same settings/cache] → Atomic writes with `.bak` and last-writer-wins; document that only one app should edit configuration at a time. Distinct single-instance names let both run.
- [DPAPI/secret-tool token mismatch] → Test a round trip both directions during implementation; if a token cannot be shared, fall back to per-app credentials and record the deviation before claiming parity.
- [Flutter text rendering/DPI differs] → Text output (the parity contract) is tested as strings, not pixels; DPI scaling is logical-pixel based like the reference.

## Migration Plan

1. Scaffold `flutter_app/` and port `domain`, `config`, `presentation` and their tests; verify decimal, validation and formatting parity first.
2. Add `platform` real/fake implementations and all provider adapters; run the fixture parity suite.
3. Add the scheduler, `AppController` and provider defaults; test backoff, coalescing, stale preservation and cross-app settings round trips.
4. Build the dashboard, settings and tray; verify responsive grid, always-visible, close-to-tray and status text.
5. Build the Windows and Linux overlay; verify projection, opacity, snapping, lock/click-through, suppression, hotkey and countdown scheduling.
6. Generate the reference parity corpus and wire the harness; document the side-by-side comparison; package Windows and Linux builds.

Rollback: delete `flutter_app/` and its CI job; the C++ app and data files are untouched, so no data migration or rollback is required.

## Open Questions

- Packaging format for the Flutter desktop builds (portable ZIP on Windows, AppImage on Linux) is deferred; it does not affect the specs or task order.
- Whether the comparison harness should shell out to the C++ binary at test time or consume committed expected-output files; start with committed files and add live comparison only if needed.
