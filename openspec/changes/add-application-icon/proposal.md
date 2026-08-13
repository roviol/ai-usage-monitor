## Why

AI Usage Monitor lacks a consistent, production-ready application identity: Linux ships a basic placeholder-style SVG, while the Windows executable and native windows do not carry a branded icon. A single source design with platform-ready derivatives will make the application recognizable in launchers, window chrome, Explorer and distributed packages.

## What Changes

- Create an original application icon that combines AI usage monitoring with the product's compact, modern visual language and remains legible at small sizes.
- Add a canonical scalable source asset plus the platform-specific derivatives needed by Windows and Linux packaging.
- Embed the application icon into the Windows executable and apply it to visible top-level windows without replacing the tray's dynamic health indicator.
- Replace the existing Linux package icon with the canonical design and keep desktop/AppImage metadata aligned with it.
- Add repeatable validation for required icon formats, embedded resources, small-size legibility and packaged outputs.

## Capabilities

### New Capabilities

- `application-icon-branding`: Defines the canonical application icon, required platform formats, desktop integration and visual/packaging verification.

### Modified Capabilities

None.

## Impact

- Adds visual assets under `assets` and updates Linux packaging assets under `packaging/linux`.
- Affects the Windows resource definition, `CMakeLists.txt`, wxWidgets window initialization and both platform packaging workflows.
- Changes application branding only; provider behavior, persisted data, tray health semantics and runtime dependencies remain unchanged.
