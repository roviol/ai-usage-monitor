## ADDED Requirements

### Requirement: Distinct application icon identity
The application MUST provide an original icon whose primary composition combines a usage or quota meter with a simple AI-associated spark or node. The icon MUST remain recognizable without text or third-party provider logos and MUST use a silhouette that is legible at common desktop icon sizes.

#### Scenario: Icon is reviewed at small sizes
- **WHEN** the committed icon is rendered at 16, 24, 32 and 48 pixels on both light and dark backgrounds
- **THEN** its outer shape, usage-meter motif and central mark remain distinguishable without relying on readable text or fine detail

#### Scenario: Icon is reviewed at launcher size
- **WHEN** the committed icon is rendered at 256 pixels or larger
- **THEN** it presents the same composition and product identity as the small-size variants without provider branding

### Requirement: Canonical and platform-ready assets
The repository MUST contain one documented high-resolution master icon and committed derivatives suitable for Windows executable resources and Linux desktop packaging. The Windows derivative MUST include 16, 24, 32, 48, 64, 128 and 256 pixel entries, and the Linux derivative MUST be a square image with transparency where required by the artwork.

#### Scenario: Asset family is validated
- **WHEN** icon asset validation runs against a clean checkout
- **THEN** it finds the master and both platform derivatives, confirms their expected formats and dimensions, and confirms all required ICO entries are present

#### Scenario: Release build runs without an image-generation service
- **WHEN** a Windows or Linux release is built from the committed repository while no image-generation service is available
- **THEN** packaging consumes the committed icon derivatives without downloading or regenerating artwork

### Requirement: Windows application integration
The Windows executable MUST embed the application icon as its primary native icon, and visible top-level application windows MUST present the same brand identity in Windows surfaces that support application icons.

#### Scenario: Executable is viewed in Explorer
- **WHEN** a newly built `ai-usage-monitor.exe` is copied to a clean directory and viewed in Windows Explorer
- **THEN** Explorer displays the committed application icon instead of a generic executable icon

#### Scenario: Dashboard is opened on Windows
- **WHEN** the user opens the dashboard from the tray
- **THEN** supported window chrome and taskbar surfaces display the application icon matching the executable

### Requirement: Linux desktop integration
The Linux AppImage layout MUST install the application icon under the `ai-usage-monitor` desktop icon name, and its desktop entry and AppImage root metadata MUST resolve to the same committed artwork.

#### Scenario: AppImage layout is assembled
- **WHEN** the Linux packaging script creates the AppDir
- **THEN** the icon exists in the expected hicolor application-icon location and the desktop entry resolves the extensionless `ai-usage-monitor` icon name

#### Scenario: AppImage is inspected in a desktop environment
- **WHEN** the packaged application is shown in a supported Linux launcher or application menu
- **THEN** it displays the same application identity used by the Windows package

### Requirement: Dynamic tray status remains independent
The system-tray icon MUST continue to communicate aggregate provider health using the existing healthy, partial, error and disabled status treatments. Application-brand integration MUST NOT replace those dynamic tray states with the static brand icon.

#### Scenario: Provider health changes
- **WHEN** aggregate provider health changes while the application is running
- **THEN** the tray icon updates to the corresponding status treatment and retains its current tooltip behavior

#### Scenario: Dashboard opens from the tray
- **WHEN** the user activates any dynamic tray status icon
- **THEN** the dashboard opens with the static application identity in its window surfaces while the tray continues showing health

### Requirement: Icon integration is release-verifiable
The project MUST provide repeatable checks or documented release assertions for asset structure, Windows resource inclusion, Linux package placement and small-size visual legibility.

#### Scenario: Windows release candidate is verified
- **WHEN** the Windows release build and package checks complete
- **THEN** they confirm the resource compiles into the executable and the portable package retains the branded executable icon

#### Scenario: Visual acceptance is recorded
- **WHEN** the icon is reviewed at required sizes and on contrasting backgrounds
- **THEN** the release evidence records that the design remains recognizable and free of clipped edges, opaque corner artifacts or illegible detail
