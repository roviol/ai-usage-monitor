## 1. Artwork and Asset Family

- [x] 1.1 Generate an original 1024×1024 RGBA master using the approved quota-ring and AI-spark concept, then select a final variant that matches the interface indigo and avoids text, provider logos and status colors.
- [x] 1.2 Commit the master under `assets` and derive the Linux PNG plus a Windows ICO containing 16, 24, 32, 48, 64, 128 and 256 px entries without adding a runtime image dependency.
- [x] 1.3 Inspect the 16, 24, 32, 48 and 256 px renderings on light and dark backgrounds, simplify small variants if necessary, and record visual acceptance in the repository's release/test documentation.

## 2. Windows Integration

- [x] 2.1 Add a native Windows resource script that declares the ICO as the executable's primary application icon and include it in `ai-usage-monitor` only for `WIN32` builds.
- [x] 2.2 Add a shared wxWidgets application-icon loader and apply the embedded icon to the dashboard and any top-level window that does not inherit it correctly.
- [x] 2.3 Extend Windows UI/package checks to confirm the executable resource and window identity while proving that all dynamic tray health states and tooltips remain unchanged.

## 3. Linux Packaging Integration

- [x] 3.1 Replace the placeholder Linux SVG with the committed PNG derivative and update `packaging/linux/build-appimage.sh` to install the matching icon at the AppDir root and hicolor application-icon path.
- [x] 3.2 Verify that `ai-usage-monitor.desktop`, `linuxdeploy --icon-file` and the assembled AppDir all resolve the same extensionless application icon identity.

## 4. Structural and Release Verification

- [x] 4.1 Add a repeatable asset validation check for the master/derivative file formats, square dimensions, transparency and required ICO size entries.
- [x] 4.2 Configure and build the Windows release, run the existing unit/fixture/UI suites, package the portable ZIP and inspect a renamed executable in a clean directory for the branded Explorer/taskbar/window icon.
- [x] 4.3 Configure and build the Linux release, run the existing test suites, assemble the AppImage/AppDir and verify launcher metadata and installed icon paths without an image-generation service.
