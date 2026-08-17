## Purpose

Define the Linux minimal usage overlay: a smaller-scope counterpart to the
Windows overlay providing an always-visible glance at quota usage without
opening the dashboard.

## ADDED Requirements

### Requirement: Optional independent Linux overlay
On Linux, the application MUST provide a minimal overlay that can be shown or
hidden independently of the normal dashboard and that consumes the same
current provider snapshots without initiating additional provider refreshes.
The overlay MUST be disabled by default for existing and new settings unless
the user enables it. The overlay MUST NOT expose click-through locking, a
global keyboard shortcut, or automatic full-screen suppression; those remain
Windows-only.

#### Scenario: User enables the overlay
- **WHEN** the user enables and shows the minimal overlay
- **THEN** the overlay appears using the latest ordered snapshots while the
  dashboard remains independently available

#### Scenario: Snapshot completes while dashboard is hidden
- **WHEN** a provider publishes a new snapshot while only the overlay is
  visible
- **THEN** the overlay updates from that snapshot without opening the
  dashboard or requesting a second refresh

### Requirement: Minimal quota presentation
The overlay MUST prioritize provider name, quota-window name, used
percentage, a thin progress representation and a concise time-to-reset
label. It MUST omit remaining-percentage rows, verbose provenance and full
error notices while retaining non-color freshness or error text. Available
non-percentage balances MUST be shown as compact values without misleading
progress tracks.

#### Scenario: Provider has multiple percentage quotas
- **WHEN** Codex or Claude publishes multiple used-percentage metrics with
  reset times
- **THEN** each visible quota row associates its own name, progress, used
  value and `reinicia en` countdown

#### Scenario: Cached metrics are stale
- **WHEN** the last valid metrics are retained after a refresh error
- **THEN** the overlay keeps their values visible and adds a concise textual
  stale or error marker

#### Scenario: Content exceeds the compact height
- **WHEN** all provider rows would exceed 40 percent of the target monitor
  work area
- **THEN** the overlay shows the rows that fit and a textual `+ N cuotas`
  summary without animation or horizontal clipping

### Requirement: Best-effort passive window behavior
The overlay MUST request borderless, always-above-normal-windows,
non-activating presentation and MUST NOT steal keyboard focus from the
current foreground application while shown or updated. Because desktop
compositors control whether always-on-top is honored, the overlay MUST
degrade to a normal visible window (rather than failing to appear or
crashing) when the compositor does not honor that request.

#### Scenario: Overlay appears while another application has focus
- **WHEN** the overlay is shown or receives updated metrics
- **THEN** it requests topmost presentation without becoming the foreground
  window or moving keyboard focus

#### Scenario: Compositor ignores always-on-top
- **WHEN** the desktop environment does not honor the overlay's topmost
  request
- **THEN** the overlay remains visible and functional as a normal window
  rather than failing to display

### Requirement: Configurable best-effort opacity
The user MUST be able to configure overlay opacity from 50 through 100
percent, with a default of 78 percent. While the overlay is shown and
receives pointer hover, it MUST temporarily use at least 95 percent opacity
and restore the configured value when hover ends, when the underlying
platform supports window transparency. When transparency is unsupported, the
overlay MUST render fully opaque rather than failing to display.

#### Scenario: User changes opacity
- **WHEN** the user saves a valid opacity value
- **THEN** the visible overlay applies it immediately and persists it for
  the next launch

#### Scenario: Stored opacity is outside the supported range
- **WHEN** settings contain an opacity below 50 or above 100 percent
- **THEN** loading clamps or replaces it with a valid readable value rather
  than creating an invisible or invalid window

#### Scenario: Platform does not support window transparency
- **WHEN** no compositor or transparency support is available
- **THEN** the overlay renders fully opaque using the configured layout
  instead of failing to appear

### Requirement: Corner placement and multi-monitor recovery
While shown, the overlay MUST be draggable and MUST snap to the nearest
corner of the current monitor work area when dragging ends. The application
MUST persist the monitor identifier and corner anchor, restore them on the
next launch, and keep the entire overlay on-screen after display changes.

#### Scenario: User drags to another corner
- **WHEN** the user releases the overlay near a different corner
- **THEN** it snaps to that corner and restores there on the next launch

#### Scenario: User moves overlay to another monitor
- **WHEN** the user drags the overlay onto another monitor and releases it
- **THEN** the selected monitor and nearest corner become the persisted
  placement

#### Scenario: Saved monitor is disconnected
- **WHEN** the application starts and the persisted monitor no longer exists
- **THEN** the overlay moves to the equivalent corner of the primary monitor
  and remains fully inside its work area

### Requirement: Tray and settings control surface
The Linux tray menu and settings window MUST expose overlay visibility,
opacity, corner and enablement controls. Changing overlay presentation
settings MUST NOT rebuild providers, clear cached snapshots or alter the
dashboard always-on-top preference.

#### Scenario: User hides overlay from tray
- **WHEN** the user selects `Ocultar overlay`
- **THEN** the overlay hides while refresh scheduling, tray operation and
  dashboard state continue normally

#### Scenario: User edits overlay settings
- **WHEN** the user saves opacity or placement preferences
- **THEN** the live overlay applies them without provider restart or
  snapshot loss

#### Scenario: Overlay is disabled
- **WHEN** the user disables overlay mode in settings
- **THEN** its window is removed while the normal dashboard and tray remain
  available

### Requirement: Lightweight countdown and rendering
Reset countdowns MUST update no more frequently than once per minute and
only when their formatted text changes. The overlay MUST use buffered
rendering without continuous animation and MUST NOT poll providers or the
network between scheduled refreshes.

#### Scenario: Countdown crosses a minute boundary
- **WHEN** a visible reset countdown changes to a different formatted minute
  value
- **THEN** the affected overlay content repaints without requesting
  provider data

#### Scenario: Overlay is idle
- **WHEN** no snapshot, countdown boundary, display or pointer event occurs
- **THEN** the overlay performs no periodic repaint, animation or network
  activity

### Requirement: Persistent backward-compatible configuration
Overlay settings MUST be stored using the same schema already shared with
the Windows overlay, with backward-compatible defaults that preserve
existing configuration files. Invalid enum, margin, monitor or opacity
values MUST fall back safely without preventing startup or modifying
provider credentials.

#### Scenario: Existing settings contain no overlay object
- **WHEN** an existing Linux installation loads settings written before this
  capability
- **THEN** the application starts with overlay mode disabled and preserves
  all existing providers and preferences

#### Scenario: Overlay preferences are saved
- **WHEN** the user changes overlay configuration and accepts settings
- **THEN** enablement, visibility, opacity, corner and monitor restore on
  the next launch
