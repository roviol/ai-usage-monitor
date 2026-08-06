## 1. Configuration and Presentation Model

- [x] 1.1 Add backward-compatible overlay settings for enablement, visibility, opacity, lock state, corner, monitor, margin and full-screen suppression, defaulting the overlay to disabled.
- [x] 1.2 Validate and safely normalize overlay opacity, corner, margin and unavailable-monitor values without affecting provider settings or encrypted credentials.
- [x] 1.3 Add serialization and migration tests for settings files with no overlay object, valid overlay preferences and malformed overlay values.
- [x] 1.4 Implement pure overlay-row projection that omits remaining percentages, preserves provider/window association, formats balances without progress and retains concise stale/error text.
- [x] 1.5 Implement reset-countdown formatting and next-minute-boundary scheduling with deterministic clock tests for future, imminent, elapsed and missing reset times.
- [x] 1.6 Implement monitor-relative height capping and `+ N cuotas` overflow projection without rotating or animating hidden rows.

## 2. Minimal Overlay Window

- [x] 2.1 Add a Windows-only `MinimalOverlayFrame` lifecycle that receives ordered snapshots independently of dashboard visibility and never initiates provider refreshes.
- [x] 2.2 Build one buffered custom-painted overlay surface for provider headings, compact quota rows, thin progress tracks, balances, reset countdowns and textual stale/error cues.
- [x] 2.3 Apply shared light/dark semantic tokens, readable translucent-surface contrast, DPI-aware typography/spacing and rounded bounds without native child controls.
- [x] 2.4 Enforce compact width and a maximum of 40 percent of target-monitor work-area height while keeping every rendered row unclipped.
- [x] 2.5 Add event-driven countdown refresh that repaints only when formatted reset text changes and performs no second-by-second update.
- [x] 2.6 Expose an accessible overlay name and concise snapshot summary while unlocked, with the dashboard and tray retained as the focusable textual equivalent.
- [x] 2.7 Handle empty, refreshing, stale, error, disabled and balance-only fixture states without expanding into full dashboard notices.

## 3. Windows Overlay Behavior

- [x] 3.1 Apply borderless, topmost, tool-window and non-activating Win32 styles so the overlay stays out of Alt+Tab and does not steal foreground focus when shown or updated.
- [x] 3.2 Implement 50–100 percent layered-window opacity with a 78 percent default and temporary minimum 95 percent hover opacity while unlocked.
- [x] 3.3 Implement locked click-through behavior by toggling the appropriate extended window style without destroying the frame or losing snapshots.
- [x] 3.4 Implement whole-surface dragging while unlocked, nearest-corner snapping and persistence of monitor identifier, corner and DPI-independent margin.
- [x] 3.5 Restore placement against the saved monitor work area and fall back to the primary monitor when topology, resolution, taskbar bounds or saved monitor availability changes.
- [x] 3.6 Recompute size and anchored position on per-monitor DPI/display events while keeping the entire overlay visible.
- [x] 3.7 Register `Ctrl+Alt+U` as a global lock toggle, unregister it on disable/exit and surface a non-fatal warning when registration conflicts.
- [x] 3.8 Add event-driven foreground/full-screen detection that optionally suppresses and restores the overlay without polling or changing the persisted visibility preference.

## 4. Application, Tray and Settings Integration

- [x] 4.1 Fan out published ordered snapshots to the overlay and dashboard without duplicating refresh work, cache writes or provider objects.
- [x] 4.2 Add tray actions for showing, hiding, locking and unlocking the overlay with labels and enabled states that reflect live overlay state.
- [x] 4.3 Add a Windows overlay settings group for enablement, visibility, opacity, corner, full-screen suppression and shortcut status using accessible native controls.
- [x] 4.4 Apply saved overlay presentation changes live without rebuilding providers, clearing snapshots or modifying the dashboard always-on-top preference.
- [x] 4.5 Ensure disabling overlay mode destroys/hides its window, removes hotkey/event hooks and leaves the tray, scheduler and dashboard fully operational.
- [x] 4.6 Preserve single-instance activation, shutdown and tray-fallback behavior with the overlay enabled, hidden, locked and suppressed.

## 5. Verification and Windows Release

- [x] 5.1 Add deterministic unit tests for row projection, overflow, countdown boundaries, opacity normalization and monitor/corner fallback decisions.
- [x] 5.2 Extend Windows UI fixtures with multiple quotas, balances, stale/error data, overflow and impending/elapsed reset states in light and dark themes.
- [x] 5.3 Add native Windows UI assertions for overlay visibility, data text, opacity changes, tray recovery, global hotkey and settings persistence.
- [x] 5.4 Verify click-through delivers pointer input to an underlying test window and that showing, locking and snapshot updates never steal foreground focus or add an Alt+Tab entry.
- [x] 5.5 Verify dragging, corner snapping and complete on-screen restoration across available monitors at 100, 125, 150 and 200 percent scaling, including monitor removal fallback.
- [x] 5.6 Verify full-screen suppression and restoration using foreground events with no polling timer, snapshot loss or persisted-visibility change.
- [x] 5.7 Run warnings-as-errors builds, unit/fixture/UI smoke tests and the Windows size, startup, idle-memory, idle-CPU, single-instance and between-refresh network gates with overlay disabled and enabled.
- [x] 5.8 Capture light, dark and low-opacity overlay screenshots, update Windows documentation and rebuild the portable ZIP with a verified SHA-256 checksum.
