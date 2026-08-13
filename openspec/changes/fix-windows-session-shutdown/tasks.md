## 1. Windows session lifecycle

- [x] 1.1 Add a Windows application-level `wxEVT_QUERY_END_SESSION` handler that accepts logoff, shutdown, and restart without delegating to frame `Close()` handlers or starting cleanup during the query phase.
- [x] 1.2 Extract an idempotent runtime-cleanup operation and reuse it from explicit tray exit and `MonitorApp::OnExit` to stop the activation watcher, remove `ready.signal`, stop scheduler and child processes, shut down overlay resources, and release tray ownership safely.
- [x] 1.3 Preserve the existing dashboard close-to-tray path for ordinary window closes and verify that an accepted but cancelled session query leaves monitoring and all UI surfaces operational.

## 2. Stable native window identity

- [x] 2.1 Give the overlay a fixed concise `AI Usage Monitor` native title and remove snapshot-, countdown-, and error-driven title updates.
- [x] 2.2 Keep the current projected usage in the overlay painting and unlocked accessible description, with dashboard and tray equivalents unchanged for locked mode.

## 3. Windows regression coverage

- [x] 3.1 Update `scripts/test-ui-windows.ps1` to assert that top-level native titles remain stable and exclude fixture provider names, account labels, quota values, reset text, and errors after snapshot updates.
- [x] 3.2 Add a native `WM_QUERYENDSESSION` check that requires an affirmative response, confirms the process remains usable when no final event follows, and rechecks normal dashboard close-to-tray behavior.
- [x] 3.3 At the end of the native UI test, send a confirmed `WM_ENDSESSION` and assert that the process exits within a bounded timeout without a force-close step, including when dashboard and overlay are active.

## 4. Verification

- [x] 4.1 Build the Windows Release target and run unit, fixture, and native Windows UI test suites with the lifecycle regression enabled.
- [ ] 4.2 Perform a manual Windows smoke test for sign-out, shutdown, and restart with the dashboard hidden and with the overlay/settings visible; confirm no blocker prompt appears and any system identification shows only the concise application title.
