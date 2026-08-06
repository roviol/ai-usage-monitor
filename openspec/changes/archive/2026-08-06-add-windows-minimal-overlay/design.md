## Context

AI Usage Monitor already owns a resident tray icon, a normal dashboard, persisted settings, provider snapshots and Windows always-on-top behavior. The new mode must reuse those snapshots while behaving like a passive desktop overlay: small, translucent, non-activating and optionally transparent to pointer input. It must not replace the dashboard, add a browser runtime, poll provider endpoints more frequently or introduce continuous animation.

The difficult parts are Windows extended window styles, safe recovery from click-through mode, per-monitor DPI placement, concise reset countdowns and preserving the existing idle-resource gates.

## Goals / Non-Goals

**Goals:**

- Provide a Windows-only overlay that exposes the essential quota information at a glance.
- Keep the overlay out of Alt+Tab, above normal windows and unable to steal focus during passive use.
- Support bounded opacity, unlocked dragging, corner snapping, multi-monitor restoration and an optional full-screen suppression mode.
- Allow pointer input to pass through a locked overlay while guaranteeing recovery through the tray and a global shortcut.
- Reuse current snapshots, freshness/error semantics, theme tokens and progress calculations.
- Persist overlay preferences with backward-compatible defaults and retain the current release budgets.

**Non-Goals:**

- Replacing or removing the full dashboard and settings window.
- Providing provider configuration, refresh buttons or other dense controls inside the overlay.
- Adding Linux/macOS overlay behavior in this change.
- Supporting arbitrary widgets, free-form themes, per-pixel visual effects, animation or second-by-second countdowns.
- Changing provider discovery, CLI invocation, quota interpretation or refresh cadence.

## Decisions

### 1. Use a separate custom-painted overlay frame

Create a dedicated `MinimalOverlayFrame` fed by the same ordered snapshots as the dashboard. It uses a borderless wxWidgets top-level frame and one buffered custom-painted content surface rather than shrinking the current dashboard or embedding native child controls.

This keeps the passive surface visually compact, avoids title-bar/control focus behavior and makes row sizing deterministic. Reusing the dashboard frame was rejected because its application bar, scrolling cards and native controls impose a larger minimum size and conflict with click-through operation.

### 2. Apply Windows styles explicitly and keep normal dashboard behavior independent

On Windows, the overlay uses `wxFRAME_NO_TASKBAR`, `wxBORDER_NONE` and always-on-top behavior plus `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`. Locking adds `WS_EX_TRANSPARENT`; unlocking removes it and enables drag handling. Style changes are applied without destroying the window so snapshots and placement remain intact.

The existing dashboard retains its current title bar, focus behavior and always-on-top option. Overlay visibility and dashboard visibility are independent.

### 3. Use bounded whole-window opacity

Use the native layered-window alpha path exposed by wxWidgets/Win32. Store opacity as an integer from 50 through 100 percent, defaulting to 78 percent. In unlocked mode, pointer hover temporarily raises opacity to at least 95 percent; locked click-through mode stays at the configured opacity because it cannot receive reliable hover input.

Whole-window opacity was chosen over a per-pixel `UpdateLayeredWindow` DIB pipeline because it is substantially simpler and more reliable with wxWidgets DPI/theme events. The 50 percent lower bound protects legibility and avoids implying that fully invisible content is still interactive.

### 4. Present compact rows and countdowns without periodic animation

Each visible percentage metric renders as provider/window label, thin used-progress track, used percentage and `reinicia en …`. Non-percentage balances render as a compact value without a progress track. Freshness/error information uses a short textual marker such as `anterior` or `error`; remaining-percentage metrics stay omitted.

Countdown labels update at minute boundaries and when a snapshot changes, not every second. Repaint occurs only when the formatted value changes. The overlay height is capped to 40 percent of the target monitor work area; overflow is summarized as `+ N cuotas` and remains fully available in the dashboard.

### 5. Persist an anchor rather than raw desktop coordinates

Store the Windows monitor device identifier, one of four corner anchors and a DPI-independent margin. While unlocked, dragging moves the overlay; releasing it snaps to the nearest corner of the current monitor work area and persists that anchor. On startup, display/DPI change or monitor removal, resolve the saved monitor, fall back to the primary monitor and clamp the frame completely inside its work area.

Raw coordinates alone were rejected because they become invalid after DPI, resolution, taskbar or monitor-topology changes.

### 6. Guarantee click-through recovery outside the overlay

The tray menu exposes `Mostrar overlay`, `Ocultar overlay`, `Bloquear clics`/`Desbloquear overlay` and `Preferencias`. Register `Ctrl+Alt+U` as the default Windows global shortcut for toggling the lock. If registration fails because another application owns the shortcut, tray recovery remains available and settings show a non-fatal warning.

The overlay itself shows a short lock indicator only while unlocked or immediately before locking. No recovery action depends on clicking a click-through window.

### 7. Use event-driven full-screen suppression

When enabled, a Windows foreground-event hook checks whether the foreground top-level window covers the target monitor. The overlay hides for that full-screen foreground window and restores when focus leaves it. The feature defaults off and does not use a polling timer.

### 8. Extend settings compatibly

Add an overlay settings object with defaults that leave the feature disabled for existing installations. Validate opacity, corner and margin values during load; unknown monitor identifiers fall back at runtime rather than invalidating the file. Saving settings updates the live overlay without rebuilding providers or losing snapshots.

### 9. Treat the passive overlay as a redundant presentation

The click-through/non-activating overlay is not the only accessible representation of its data. The dashboard and tray continue to expose the same textual status. When unlocked, the overlay exposes a concise accessible name and description, but it does not introduce focusable row controls that would contradict passive behavior.

## Risks / Trade-offs

- [Low opacity can make text unreadable on detailed backgrounds] → Enforce a 50 percent minimum, use a high-contrast surface and raise opacity while unlocked/hovered.
- [Click-through can make the overlay appear impossible to control] → Keep independent tray actions and a global unlock shortcut; never require an overlay click to recover.
- [Global shortcut conflicts with another application] → Treat registration failure as non-fatal and preserve tray recovery.
- [Saved position becomes off-screen after monitor or DPI changes] → Persist monitor/anchor semantics and clamp to the current work area on every topology change.
- [Many quota windows make the overlay intrusive] → Cap height relative to the monitor and summarize overflow without rotating or animating rows.
- [Full-screen detection may misclassify borderless maximized windows] → Default the option off and compare against the monitor rectangle with a small tolerance.
- [Minute countdown updates can affect idle CPU] → Schedule only the next meaningful boundary, avoid animation and retain the release CPU gate.
- [Windows-only branches can leak into Linux builds] → Isolate Win32 style, monitor, hotkey and event-hook code behind the platform boundary and compile guards.

## Migration Plan

1. Extend settings loading and saving with overlay defaults while preserving schema compatibility for existing files.
2. Add the overlay frame and snapshot fan-out behind a disabled-by-default setting.
3. Add Win32 style, monitor, hotkey and foreground-hook adapters.
4. Add settings and tray controls, then enable deterministic UI fixtures and tests.
5. Rebuild the Windows portable package and rerun startup, memory, CPU, network and single-instance gates.

Rollback consists of disabling the overlay setting or reverting the new frame/platform adapter; the dashboard and provider pipeline remain independent and require no data migration.

## Open Questions

- Whether a future change should allow users to select individual quota rows; this proposal initially shows enabled providers in snapshot order and summarizes overflow.
