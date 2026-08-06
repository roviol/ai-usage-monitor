# Windows Minimal Overlay Specification

## Purpose

Define the Windows-only minimal usage overlay, including its compact presentation, passive window behavior, controls, placement, persistence, accessibility, and resource constraints.

## Requirements

### Requirement: Optional independent Windows overlay
On Windows, the application MUST provide a minimal overlay that can be shown or hidden independently of the normal dashboard and that consumes the same current provider snapshots without initiating additional provider refreshes. The overlay MUST be disabled by default for existing and new settings unless the user enables it.

#### Scenario: User enables the overlay
- **WHEN** the user enables and shows the minimal overlay
- **THEN** the overlay appears using the latest ordered snapshots while the dashboard remains independently available

#### Scenario: Snapshot completes while dashboard is hidden
- **WHEN** a provider publishes a new snapshot while only the overlay is visible
- **THEN** the overlay updates from that snapshot without opening the dashboard or requesting a second refresh

#### Scenario: Application runs outside Windows
- **WHEN** the same settings are loaded on a non-Windows platform
- **THEN** overlay controls and behavior remain unavailable without preventing the normal application from starting

### Requirement: Minimal quota presentation
The overlay MUST prioritize provider name, quota-window name, used percentage, a thin progress representation and a concise time-to-reset label. It MUST omit remaining-percentage rows, verbose provenance and full error notices while retaining non-color freshness or error text. Available non-percentage balances MUST be shown as compact values without misleading progress tracks.

#### Scenario: Provider has multiple percentage quotas
- **WHEN** Codex or Claude publishes multiple used-percentage metrics with reset times
- **THEN** each visible quota row associates its own name, progress, used value and `reinicia en` countdown

#### Scenario: Cached metrics are stale
- **WHEN** the last valid metrics are retained after a refresh error
- **THEN** the overlay keeps their values visible and adds a concise textual stale or error marker

#### Scenario: Provider reports a balance
- **WHEN** a provider exposes a monetary balance instead of a percentage quota
- **THEN** the overlay renders the formatted balance without a percentage bar

#### Scenario: Content exceeds the compact height
- **WHEN** all provider rows would exceed 40 percent of the target monitor work area
- **THEN** the overlay shows the rows that fit and a textual `+ N cuotas` summary without animation or horizontal clipping

### Requirement: Passive topmost window behavior
The overlay MUST be borderless, always above normal windows, absent from Alt+Tab and non-activating during passive use. Showing or updating it MUST NOT steal keyboard focus from the current foreground application.

#### Scenario: Overlay appears while another application has focus
- **WHEN** the overlay is shown or receives updated metrics
- **THEN** it remains topmost without becoming the foreground window or moving keyboard focus

#### Scenario: User cycles applications
- **WHEN** the user invokes the Windows Alt+Tab switcher
- **THEN** the overlay is not listed as an application window

### Requirement: Configurable safe opacity
The user MUST be able to configure overlay opacity from 50 through 100 percent, with a default of 78 percent. While the overlay is unlocked and receives pointer hover, it MUST temporarily use at least 95 percent opacity and restore the configured value when hover ends.

#### Scenario: User changes opacity
- **WHEN** the user saves a valid opacity value
- **THEN** the visible overlay applies it immediately and persists it for the next launch

#### Scenario: Stored opacity is outside the supported range
- **WHEN** settings contain an opacity below 50 or above 100 percent
- **THEN** loading clamps or replaces it with a valid readable value rather than creating an invisible or invalid window

#### Scenario: Pointer enters an unlocked overlay
- **WHEN** the pointer enters the overlay while click-through is disabled
- **THEN** opacity increases to at least 95 percent without changing the stored preference

### Requirement: Lockable click-through interaction
The overlay MUST support an unlocked mode for dragging and a locked click-through mode in which pointer input reaches the window underneath. The user MUST be able to toggle the lock from the tray and through a Windows global shortcut without clicking the overlay.

#### Scenario: Overlay is locked
- **WHEN** the user activates `Bloquear clics`
- **THEN** subsequent pointer input within the overlay bounds is delivered to the underlying application

#### Scenario: User recovers a click-through overlay from the tray
- **WHEN** the overlay is locked and the user selects `Desbloquear overlay` from the tray
- **THEN** click-through is removed and the overlay can be dragged again

#### Scenario: User toggles lock with the global shortcut
- **WHEN** the registered `Ctrl+Alt+U` shortcut is pressed
- **THEN** the overlay toggles between locked and unlocked without activating the overlay window

#### Scenario: Global shortcut registration fails
- **WHEN** Windows reports that the configured shortcut is already registered
- **THEN** the application remains operational, preserves tray recovery and presents a non-fatal warning in settings

### Requirement: Corner placement and multi-monitor recovery
While unlocked, the overlay MUST be draggable and MUST snap to the nearest corner of the current monitor work area when dragging ends. The application MUST persist the monitor identifier and corner anchor, restore them using DPI-aware margins and keep the entire overlay on-screen after display changes.

#### Scenario: User drags to another corner
- **WHEN** the user releases an unlocked overlay near a different corner
- **THEN** it snaps to that corner and restores there on the next launch

#### Scenario: User moves overlay to another monitor
- **WHEN** the user drags the overlay onto another monitor and releases it
- **THEN** the selected monitor and nearest corner become the persisted placement

#### Scenario: Saved monitor is disconnected
- **WHEN** the application starts and the persisted monitor no longer exists
- **THEN** the overlay moves to the equivalent corner of the primary monitor and remains fully inside its work area

#### Scenario: Display DPI or work area changes
- **WHEN** Windows reports a DPI, resolution, orientation or taskbar work-area change
- **THEN** the overlay recomputes its size and anchored position without clipping or losing snapshots

### Requirement: Tray and settings control surface
The Windows tray menu and settings window MUST expose overlay visibility, lock state, opacity, corner, full-screen suppression and enablement controls. Changing overlay presentation settings MUST NOT rebuild providers, clear cached snapshots or alter the dashboard always-on-top preference.

#### Scenario: User hides overlay from tray
- **WHEN** the user selects `Ocultar overlay`
- **THEN** the overlay hides while refresh scheduling, tray operation and dashboard state continue normally

#### Scenario: User edits overlay settings
- **WHEN** the user saves opacity, placement or full-screen preferences
- **THEN** the live overlay applies them without provider restart or snapshot loss

#### Scenario: Overlay is disabled
- **WHEN** the user disables overlay mode in settings
- **THEN** its window and global shortcut are removed while the normal dashboard and tray remain available

### Requirement: Event-driven full-screen suppression
When full-screen suppression is enabled, the overlay MUST hide while another foreground top-level window covers its target monitor and MUST restore after that full-screen condition ends. Detection MUST be event-driven and MUST NOT add a periodic polling or repaint loop.

#### Scenario: Full-screen application takes foreground
- **WHEN** suppression is enabled and another application covers the target monitor as the foreground window
- **THEN** the overlay hides without changing the user's enabled or visible preference

#### Scenario: User leaves full-screen application
- **WHEN** the foreground full-screen condition ends
- **THEN** the overlay returns to its prior visible state and anchored position without stealing focus

#### Scenario: Suppression is disabled
- **WHEN** another application enters full screen while suppression is disabled
- **THEN** the overlay remains visible according to its normal visibility setting

### Requirement: Lightweight countdown and rendering
Reset countdowns MUST update no more frequently than once per minute and only when their formatted text changes. The overlay MUST use buffered native rendering without continuous animation and MUST continue satisfying Windows package-size, startup, idle-memory, idle-CPU and between-refresh network gates.

#### Scenario: Countdown crosses a minute boundary
- **WHEN** a visible reset countdown changes to a different formatted minute value
- **THEN** the affected overlay content repaints without requesting provider data

#### Scenario: Overlay is idle
- **WHEN** no snapshot, countdown boundary, display, pointer or foreground event occurs
- **THEN** the overlay performs no periodic repaint, animation or network activity

#### Scenario: Windows portable package is measured
- **WHEN** the overlay-enabled build is subjected to existing release gates
- **THEN** package size, startup, memory, idle CPU, single-instance and between-refresh network checks remain within their established limits

### Requirement: Persistent backward-compatible configuration
Overlay settings MUST be stored with backward-compatible defaults that preserve existing configuration files. Invalid enum, margin, monitor or opacity values MUST fall back safely without preventing startup or modifying provider credentials.

#### Scenario: Existing settings contain no overlay object
- **WHEN** an existing installation loads settings written before this capability
- **THEN** the application starts with overlay mode disabled and preserves all existing providers and preferences

#### Scenario: Overlay preferences are saved
- **WHEN** the user changes overlay configuration and accepts settings
- **THEN** enablement, visibility, opacity, lock, corner, monitor, margin and full-screen suppression restore on the next launch

#### Scenario: Overlay configuration is invalid
- **WHEN** one or more overlay values are malformed or reference an unavailable monitor
- **THEN** safe overlay defaults are used while unrelated settings and secrets remain intact

### Requirement: Accessible equivalent information
The overlay MUST expose a concise accessible name and description while unlocked, and the same usage, reset and error information MUST remain available through the normal dashboard or tray when the overlay is non-activating or click-through.

#### Scenario: Assistive technology cannot focus locked overlay rows
- **WHEN** the overlay is locked and intentionally non-activating
- **THEN** the dashboard and tray continue to provide textual equivalents for every displayed quota status

#### Scenario: Overlay is unlocked
- **WHEN** assistive technology inspects the unlocked overlay window
- **THEN** it reports a descriptive overlay name and summary instead of unlabeled custom controls
