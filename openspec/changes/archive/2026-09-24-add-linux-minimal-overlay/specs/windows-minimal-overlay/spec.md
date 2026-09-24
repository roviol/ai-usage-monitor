## MODIFIED Requirements

### Requirement: Optional independent Windows overlay
On Windows, the application MUST provide a minimal overlay that can be shown or hidden independently of the normal dashboard and that consumes the same current provider snapshots without initiating additional provider refreshes. The overlay MUST be disabled by default for existing and new settings unless the user enables it.

#### Scenario: User enables the overlay
- **WHEN** the user enables and shows the minimal overlay
- **THEN** the overlay appears using the latest ordered snapshots while the dashboard remains independently available

#### Scenario: Snapshot completes while dashboard is hidden
- **WHEN** a provider publishes a new snapshot while only the overlay is visible
- **THEN** the overlay updates from that snapshot without opening the dashboard or requesting a second refresh

#### Scenario: Application runs on Linux
- **WHEN** the same settings are loaded on Linux
- **THEN** the Windows-specific overlay controls (click-through lock, global shortcut, full-screen suppression) remain unavailable, and the separate `linux-minimal-overlay` capability governs overlay behavior there instead

#### Scenario: Application runs outside Windows and Linux
- **WHEN** the same settings are loaded on a platform other than Windows or Linux
- **THEN** overlay controls and behavior remain unavailable without preventing the normal application from starting
