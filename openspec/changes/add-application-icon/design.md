## Context

The repository currently contains a simple Linux-only SVG built from a dark rounded square and a usage ring. Windows has no `.ico` or resource script, so Explorer and the packaged executable use a generic icon. At runtime, `TrayIcon` deliberately generates colored circles from provider health; that status signal has different semantics from permanent product branding and must remain independent.

The application is a portable C++20/wxWidgets desktop program built with CMake for Windows and Linux. Icon integration therefore has to work without a runtime asset lookup, a new application framework or a new dependency in the shipped package.

## Goals / Non-Goals

**Goals:**

- Give AI Usage Monitor an original, recognizable identity based on monitoring AI quota usage.
- Keep the silhouette and primary motif readable from 16 px through launcher-scale presentation.
- Commit reviewable source artwork and ready-to-package Windows/Linux derivatives.
- Embed the Windows icon in the executable and use the brand icon for application windows and desktop packaging.
- Preserve the tray icon's existing dynamic health colors and tooltip behavior.

**Non-Goals:**

- Renaming the product or creating a broader brand system, wordmark or marketing campaign.
- Replacing health/status iconography inside the dashboard or system tray.
- Adding icon generation tools to the end-user runtime or regenerating artwork during every normal build.
- Supporting macOS packaging in this change.

## Decisions

### 1. Use a quota-ring and AI-spark composition

The icon will use a rounded deep-navy tile, a bold open circular usage ring and a simple central spark/node. The ring communicates measured capacity, while the spark distinguishes the application from a generic system monitor. The primary accent will be the interface indigo (`#4A5BD6`) with a lighter highlight; health green, amber and red will not define the brand artwork because those colors already have runtime status meaning.

The artwork will contain no letters, provider logos, thin strokes, small counters, gradients essential to recognition or text that becomes unreadable at small sizes. A wordmark and a literal robot/brain illustration were rejected because they become noisy in taskbars and imply capabilities the monitor does not provide.

### 2. Commit a high-resolution master and platform derivatives

Generate and visually review a square 1024×1024 RGBA master under `assets`, then derive and commit a multi-resolution Windows `.ico` and the Linux PNG used by desktop/AppImage packaging. The ICO will contain at least 16, 24, 32, 48, 64, 128 and 256 px entries; the smallest entries may receive pixel-level simplification instead of blind downscaling. A compact code-embeddable window variant may be added when needed by wxWidgets so installed and portable execution do not depend on locating an external file.

Committed derivatives keep release builds deterministic and avoid adding an image conversion dependency to users or CI. The current Linux SVG will be replaced rather than retained as a competing source of truth; retaining two independently editable designs was rejected because they would drift.

### 3. Integrate Windows through a native resource script

Add a Windows resource file that declares the ICO as the executable's primary icon, and include it in the `ai-usage-monitor` target only under `WIN32`. The top-level dashboard will receive the same icon through a shared UI helper or embedded icon bundle; owned dialogs inherit it where the platform supports inheritance, with explicit assignment only if verification shows it is required.

Native resource embedding makes Explorer, shortcuts and taskbar/window chrome work even when the portable executable is moved by itself. Copying a loose ICO next to the executable was rejected because Explorer does not use it as the executable identity and users can separate it from the binary.

### 4. Use the same artwork in Linux packaging metadata

Replace `packaging/linux/ai-usage-monitor.svg` with the committed PNG derivative, update `build-appimage.sh` to install it in the appropriate hicolor application-icon directory, and continue referencing the extensionless `ai-usage-monitor` name from the desktop entry. AppImage root metadata and `linuxdeploy --icon-file` will point to that same artifact.

This preserves freedesktop icon lookup conventions while ensuring the packaged icon matches Windows. Keeping the placeholder SVG was rejected because it would present a different brand on each platform.

### 5. Separate visual approval from structural verification

Review the master and rasterized 16, 24, 32, 48 and 256 px representations against light and dark backgrounds. Automated checks will cover file presence, square dimensions, ICO size entries, transparency and build/package references. Windows verification will inspect the built executable and visible dashboard/taskbar icon; Linux verification will inspect the AppDir icon locations and desktop metadata.

Pixel-perfect screenshot comparison is not suitable for shell/taskbar rendering across operating systems, so the acceptance record will combine deterministic structural checks with a documented visual review.

## Risks / Trade-offs

- [Generated artwork may contain soft details that collapse at taskbar sizes] → Treat 16–32 px views as primary acceptance targets and simplify those ICO entries when needed.
- [Explorer may cache an older executable icon] → Verify with a renamed build artifact or a clean test directory and document cache-aware smoke-test steps.
- [A resource compiles on MSVC but breaks non-Windows builds] → Add the `.rc` source only inside the existing `WIN32` CMake branch and run both platform build gates.
- [Multiple committed formats can drift] → Name the 1024 px master as the source, document derivative sizes and validate that package references point to the committed family.
- [Applying the brand icon to the tray would hide health state] → Leave `TrayIcon::MakeStatusIcon` and its health aggregation unchanged and test each status color after integration.

## Migration Plan

1. Generate and approve the master icon plus its small-size representations.
2. Commit the master and Windows/Linux derivatives, replacing the placeholder Linux artwork.
3. Add Windows resource and wxWidgets window integration, then update Linux AppImage paths.
4. Run icon-structure checks, builds and platform packaging smoke tests.
5. Roll back by removing the resource/window integration and restoring the previous Linux SVG; no user data or configuration migration is involved.

## Open Questions

- During implementation, confirm whether the target wxWidgets/wxGTK build automatically resolves the installed desktop icon for all top-level windows; if not, use the committed embedded window variant.
- Confirm the final small-size simplification after reviewing actual Windows taskbar and Linux launcher rendering rather than deciding from the 1024 px master alone.
