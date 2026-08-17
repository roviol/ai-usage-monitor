## 1. Environment check

- [x] 1.1 Record the Linux distro/version (`lsb_release -a` or `/etc/os-release`) and confirm it is Ubuntu 24.04 or a close equivalent covered by `docs/linux.md`.
- [x] 1.2 Check for `cmake`, `ninja`, `g++`/`gcc`, `pkg-config`, `curl`, and `secret-tool` already present (`--version` / `which`) so we know what actually needs installing.

## 2. Install build dependencies

- [x] 2.1 Install `build-essential cmake ninja-build libgtk-3-dev libcurl4-openssl-dev libsecret-tools` via `apt-get` as documented in `docs/linux.md`.
- [x] 2.2 Verify CMake version satisfies the `cmake_minimum_required(VERSION 3.25)` in `CMakeLists.txt`; if the distro package is older, note it and resolve (e.g. `pip`/upstream Kitware repo) before continuing.
- [x] 2.3 Note any package name differences or missing packages for the actual distro/version in use, for later doc fixes.

## 3. Configure and build

- [x] 3.1 Run `cmake --preset linux-release` from the repo root and capture the full output.
- [x] 3.2 If configure fails (missing `CURL::libcurl`, wxWidgets fetch/build issues in `cmake/Dependencies.cmake`, GTK3 discovery, etc.), diagnose and fix the root cause — in the build environment first, and in the CMake/dependency files if the fix is a genuine defect rather than a one-off local gap. (Configure succeeded cleanly on the first try; nothing to fix.)
- [x] 3.3 Run `cmake --build --preset linux-release --parallel` and capture the full output.
- [x] 3.4 If the build fails under `-Wall -Wextra -Wpedantic -Werror` (see `ai_usage_strict` in `CMakeLists.txt`) or due to Linux-only code paths (`src/platform/linux_platform.cpp`), fix the failing code and rebuild until it succeeds cleanly. (Build succeeded cleanly, 1162/1162, no warnings/errors; nothing to fix.)
- [ ] 3.5 Optionally repeat steps 3.1–3.4 for the `linux-debug` preset if useful for debugging any issues found. (Skipped — release build succeeded with no issues to debug.)

## 4. Run automated tests

- [x] 4.1 Run `ctest --preset linux-release --output-on-failure`.
- [x] 4.2 Triage any failing tests (`ai-usage-unit-tests`, `ai-usage-fixture-tests`): distinguish genuine Linux-specific bugs from environment gaps (e.g. missing `secret-tool`/Secret Service, no network for a fixture) and fix or document accordingly. (Both suites passed on the first run — no triage needed.)
- [x] 4.3 Re-run `ctest` until the suite passes, or record any tests that are expected to fail/skip in this environment and why. (100% passed: 2/2 tests, ~1s total.)

## 5. Smoke-run the application

- [x] 5.1 Launch the built `ai-usage-monitor` binary from `build/linux-release`. (Launched under an X11-forwarded XFCE session; found and fixed a Linux-only startup bug along the way — see 6.1.)
- [x] 5.2 Verify tray icon behavior per `docs/linux.md` (StatusNotifier host present → tray icon, left-click dashboard, context menu, refresh, settings, exit, single-instance activation) or, if no tray host is available, verify the dashboard fallback is fully usable. (XFCE panel hosted the tray icon; it rendered the live health-colored icon and tooltip with real Codex/Claude data pulled from the local CLIs.)
- [x] 5.3 Exercise the Settings dialog (provider enable/disable, refresh interval) and confirm the dashboard renders cards/progress bars without crashing. (Verified via `AI_USAGE_UI_FIXTURES=1`: dashboard cards/progress bars render correctly; Settings dialog opens with provider list, identity fields, refresh-interval stepper, all functional.)
- [x] 5.4 Confirm clean exit (no leftover process, no crash on close). (Closed the window; process exited with no leftover PID.)

## 6. Wrap up findings

- [x] 6.1 Update `docs/linux.md` (and `CMakePresets.json` / `cmake/Dependencies.cmake` if needed) with any corrections discovered while working through steps 1-5. Added a note confirming Debian 13 (trixie) also works with the documented steps unchanged. Fixed a genuine Linux-only startup defect in `src/ui/app_icon.cpp`: `LoadApplicationIcons()` decoded the embedded PNG app icon via `wxBitmap::NewFromPNGData` without ever registering wx's PNG image handler; on Windows this path is skipped (a native `HICON` is found first), so the bug was invisible there, but on Linux it always hit the PNG path and popped a "No image handler for type 15 defined" warning dialog on every startup. Fixed by lazily registering `wxPNGHandler` before the decode. Verified fixed by rebuilding and relaunching — no warning dialog, and the window/taskbar icon now renders instead of a blank icon.
- [x] 6.2 Summarize the outcome (build clean? tests green? app runs?) and list any real product bugs found as candidates for their own follow-up change, rather than fixing unrelated functional behavior here. See proposal/outcome summary below — build clean, tests green (2/2), app runs and was smoke-tested end to end; one Linux-only startup bug found and fixed in this change (see 6.1); no other product bugs found.
