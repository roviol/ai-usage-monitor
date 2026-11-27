## Purpose

Define the minimal usage overlay of the Flutter application so that it provides the same glanceable quota information and interaction as the C++ reference overlay on Windows and Linux, including platform-specific locking, full-screen suppression and a recovery shortcut.

## ADDED Requirements

### Requirement: Optional independent overlay
The Flutter application SHALL provide a minimal overlay, disabled by default, that can be shown or hidden independently of the dashboard and that consumes the same current snapshots without initiating additional provider refreshes. The overlay MUST be available on Windows and Linux.

#### Scenario: User enables the overlay
- **WHEN** the user enables and shows the overlay
- **THEN** it appears with the latest ordered snapshots while the dashboard remains independently available

#### Scenario: Snapshot completes while dashboard is hidden
- **WHEN** a provider publishes a new snapshot while only the overlay is visible
- **THEN** the overlay updates without opening the dashboard or requesting a second refresh

#### Scenario: Overlay is disabled
- **WHEN** the user disables overlay mode
- **THEN** its window and any global shortcut are removed while the dashboard and tray remain available

### Requirement: Minimal quota presentation
The overlay SHALL prioritize provider name, quota-window name, used percentage, a thin progress representation and a concise time-to-reset label. It MUST omit remaining-percentage rows, verbose provenance and full error notices while keeping a textual stale or error marker. Available non-percentage balances MUST be shown as compact values without progress tracks.

#### Scenario: Multiple percentage quotas
- **WHEN** Codex or Claude publishes several used-percentage metrics with reset times
- **THEN** each visible row shows its own name, progress, used value and a reset countdown

#### Scenario: Cached metrics are stale
- **WHEN** last valid metrics are retained after a refresh error
- **THEN** their values remain visible with a concise stale or error marker

#### Scenario: Balance is shown
- **WHEN** a provider exposes a monetary balance
- **THEN** the overlay shows the formatted balance without a percentage bar

#### Scenario: Content exceeds the compact height
- **WHEN** all rows would exceed 40 percent of the target monitor work area
- **THEN** the overlay shows the rows that fit plus a textual additional-count summary, with no animation or horizontal clipping

### Requirement: Passive window behavior
The overlay SHALL be borderless and always above normal windows, SHALL NOT appear in the task switcher, and SHALL NOT steal keyboard focus when shown or updated. Where the platform cannot guarantee a behavior, the overlay MUST degrade to a visible, functional window instead of failing to appear.

#### Scenario: Overlay appears while another application has focus
- **WHEN** the overlay is shown or receives updated metrics
- **THEN** it stays on top without becoming the foreground window or moving keyboard focus

#### Scenario: Task switching
- **WHEN** the user switches applications
- **THEN** the overlay is not listed as an application window

#### Scenario: Compositor ignores topmost
- **WHEN** the desktop environment does not honor the topmost request
- **THEN** the overlay remains visible and functional as a normal window

### Requirement: Configurable opacity
The user SHALL be able to configure overlay opacity from 50 through 100 percent, defaulting to 78. While shown and hovered, the overlay MUST temporarily use at least 95 percent opacity and restore the configured value when hover ends, when window transparency is supported; otherwise it MUST render fully opaque.

#### Scenario: User changes opacity
- **WHEN** the user saves a valid opacity
- **THEN** the visible overlay applies it immediately and persists it for the next launch

#### Scenario: Stored opacity is invalid
- **WHEN** settings contain an opacity outside 50–100
- **THEN** loading clamps it to a valid readable value

#### Scenario: Pointer hovers the overlay
- **WHEN** the pointer enters the overlay
- **THEN** opacity increases to at least 95 percent without changing the stored preference

### Requirement: Lockable click-through interaction on Windows
On Windows, the overlay SHALL support an unlocked mode for dragging and a locked click-through mode in which pointer input reaches the window underneath, toggleable from the tray and through the global shortcut `Ctrl+Alt+U` without clicking the overlay. If the shortcut cannot be registered, the application MUST remain operational, preserve tray recovery and warn in settings.

#### Scenario: Overlay is locked
- **WHEN** the user locks click-through
- **THEN** subsequent pointer input within the overlay bounds reaches the underlying application

#### Scenario: Overlay is recovered from the tray
- **WHEN** the overlay is locked and the user chooses to unlock it from the tray
- **THEN** click-through is removed and the overlay can be dragged again

#### Scenario: Global shortcut toggles lock
- **WHEN** `Ctrl+Alt+U` is pressed
- **THEN** the lock toggles without activating the overlay window

#### Scenario: Shortcut registration fails
- **WHEN** another application already owns the shortcut
- **THEN** the app keeps running and shows a non-fatal warning in settings

### Requirement: Corner placement and multi-monitor recovery
While shown, the overlay SHALL be draggable and SHALL snap to the nearest corner of the current monitor work area when dragging ends. The application SHALL persist the monitor identifier and corner anchor, restore them on the next launch, and keep the entire overlay on screen after display changes.

#### Scenario: User drags to another corner
- **WHEN** the user releases the overlay near a different corner
- **THEN** it snaps there and restores there on the next launch

#### Scenario: User moves the overlay to another monitor
- **WHEN** the user releases the overlay on another monitor
- **THEN** that monitor and nearest corner become the persisted placement

#### Scenario: Saved monitor is disconnected
- **WHEN** the application starts and the persisted monitor no longer exists
- **THEN** the overlay moves to the equivalent corner of the primary monitor and stays inside its work area

### Requirement: Event-driven full-screen suppression on Windows
When suppression is enabled on Windows, the overlay SHALL hide while another foreground top-level window covers its target monitor and SHALL restore afterward. Detection MUST be event-driven and MUST NOT add periodic polling or repaint.

#### Scenario: Full-screen application takes focus
- **WHEN** suppression is enabled and another application covers the target monitor
- **THEN** the overlay hides without changing the user's enabled or visible preference

#### Scenario: User leaves full-screen
- **WHEN** the full-screen condition ends
- **THEN** the overlay returns to its prior visible state without stealing focus

#### Scenario: Suppression is disabled
- **WHEN** another application enters full screen while suppression is disabled
- **THEN** the overlay remains visible per its normal visibility setting

### Requirement: Lightweight countdown and rendering
Reset countdowns SHALL update no more frequently than once per minute and only when their formatted text changes. The overlay MUST use buffered rendering without continuous animation and MUST NOT poll providers or the network between scheduled refreshes.

#### Scenario: Countdown crosses a minute boundary
- **WHEN** a visible reset countdown changes to a different formatted minute value
- **THEN** the overlay repaints without requesting provider data

#### Scenario: Overlay is idle
- **WHEN** no snapshot, countdown, display or pointer event occurs
- **THEN** the overlay performs no periodic repaint, animation or network activity

### Requirement: Overlay control surface and persistence
The tray menu and settings window SHALL expose overlay visibility, lock state, opacity, corner, full-screen suppression and enablement controls. Overlay settings SHALL use the same schema and safe fallbacks as the reference, and changing them MUST NOT rebuild providers, clear cached snapshots or alter the dashboard always-visible preference.

#### Scenario: User hides the overlay from the tray
- **WHEN** the user chooses to hide the overlay
- **THEN** it hides while refresh scheduling, tray operation and dashboard state continue normally

#### Scenario: Invalid overlay configuration
- **WHEN** overlay values are malformed or reference an unavailable monitor
- **THEN** safe defaults are used without preventing startup or modifying provider credentials
