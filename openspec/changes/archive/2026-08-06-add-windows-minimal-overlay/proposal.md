## Why

The full dashboard is useful for inspection and configuration, but it occupies too much screen space to remain visible while working. Windows users need an optional, unobtrusive overlay that keeps quota usage and time-to-reset glanceable without stealing focus or blocking interaction with the application underneath.

## What Changes

- Add a Windows-only minimal overlay mode alongside the existing dashboard; the normal dashboard remains unchanged and fully available.
- Present only provider identity, quota-window name, used percentage, a thin progress bar and a concise reset countdown; non-percentage balances use an equally compact text treatment.
- Make the overlay borderless, always on top, absent from Alt+Tab and non-activating during passive use.
- Add configurable opacity with a more readable hover opacity and a safe lower bound for text legibility.
- Allow dragging while unlocked, snapping to a screen corner, remembering the selected monitor and restoring a DPI-safe on-screen position.
- Add a lockable click-through mode so pointer input reaches the window below, with recovery controls available from the tray and a keyboard shortcut.
- Add tray actions and settings for showing, hiding, locking and configuring the overlay without replacing existing dashboard controls.
- Optionally hide the overlay while another application is running full screen.

## Capabilities

### New Capabilities

- `windows-minimal-overlay`: Covers the compact quota presentation, borderless always-on-top window behavior, opacity, click-through locking, positioning, persistence, tray recovery and Windows-specific safety behavior.

### Modified Capabilities

None.

## Impact

- Affects the Windows wxWidgets UI, tray menu, settings schema and persistence, snapshot presentation, multi-monitor/DPI handling and Win32 extended window styles.
- Adds no external UI runtime or network behavior and does not change provider collection, quota semantics or refresh scheduling.
- Requires Windows UI fixtures and release checks for focus, click-through recovery, placement, opacity, DPI scaling, idle CPU and package size.
- Linux behavior and packaging remain unchanged; overlay controls must be absent or explicitly unavailable outside Windows.
