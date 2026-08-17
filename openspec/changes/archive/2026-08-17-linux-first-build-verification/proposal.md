## Why

AI Usage Monitor has been developed and released for Windows so far; the CI matrix
and `docs/linux.md` describe the Linux build, but no one has actually built and run
it on a Linux machine yet. Before trusting the documented steps or shipping a Linux
package, we need to run through them on real hardware, confirm the toolchain and
dependencies are correctly specified, and record any gaps or fixes needed.

## What Changes

- Install the Ubuntu/Debian build dependencies listed in `docs/linux.md`
  (`build-essential`, `cmake`, `ninja-build`, `libgtk-3-dev`,
  `libcurl4-openssl-dev`, `libsecret-tools`) and record any that are missing,
  misnamed, or need adjustment for the actual distro in use.
- Configure and build the `linux-release` (and if useful, `linux-debug`) CMake
  preset, resolving any configure/compile errors encountered (fetched
  dependencies, `wxGTK`/GTK3 discovery, compiler warnings under `-Werror`, etc.).
- Run the CTest suite (`ctest --preset linux-release`) and the unit/fixture test
  binaries, and triage any failures that are specific to running on Linux for
  the first time.
- Launch the built `ai-usage-monitor` binary and do a smoke check: tray icon
  (or dashboard fallback), dashboard, settings dialog, and clean exit, per the
  desktop acceptance notes in `docs/linux.md`.
- Document any corrections needed to `docs/linux.md`, `CMakePresets.json`,
  `cmake/Dependencies.cmake`, or the source itself as a result of this first
  run, and fix straightforward build-breaking issues found along the way.

This is a verification/bring-up effort, not a new feature: no product behavior
is intended to change. If the run surfaces a real functional bug, it will be
handled as its own follow-up change with an appropriate spec delta rather than
folded in here.

## Capabilities

No capability specs are introduced or modified by this change — it verifies
existing documented Linux build/test/run behavior and fixes build-time issues
if any are found. `skip_specs: true` is set in `.openspec.yaml` accordingly.

## Impact

- **Build system**: `CMakeLists.txt`, `CMakePresets.json`, `cmake/Dependencies.cmake`
  (only if the first Linux configure/build surfaces a real defect).
- **Docs**: `docs/linux.md` (corrections/clarifications from the actual run).
- **Local environment**: installs Linux system packages
  (`build-essential`, `cmake`, `ninja-build`, `libgtk-3-dev`,
  `libcurl4-openssl-dev`, `libsecret-tools`) and a `build/linux-release`
  (and optionally `build/linux-debug`) directory under the repo.
- **No runtime/product behavior change** is expected; this change is scoped to
  build, test, and smoke-run verification on Linux.
