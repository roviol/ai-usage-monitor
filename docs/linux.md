# Linux build and tray notes

Also verified on Debian 13 (trixie): the same `apt-get` package names and
CMake presets configure, build, and pass `ctest` without changes.

Ubuntu 24.04 build dependencies:

```sh
sudo apt-get install build-essential cmake ninja-build libgtk-3-dev libcurl4-openssl-dev libsecret-tools
cmake --preset linux-release
cmake --build --preset linux-release --parallel
ctest --preset linux-release
```

Create an AppImage after installing `linuxdeploy` and `appimagetool` (CI pins
and verifies the official x86-64 release assets before running this command):

```sh
packaging/linux/build-appimage.sh build/linux-release dist
```

## Per-machine install with autostart

`scripts/install-linux.sh` builds and installs the app for the current user
(no root needed): binary under `~/.local/share/ai-usage-monitor`, a launcher
symlink at `~/.local/bin/ai-usage-monitor`, a menu entry, the app icon, and a
session autostart entry in `~/.config/autostart`. Re-run it any time after
changing the code to rebuild incrementally and reinstall over the previous
copy:

```sh
scripts/install-linux.sh            # build + install
scripts/install-linux.sh --start    # also launch it now
scripts/install-linux.sh --test     # run ctest before installing
scripts/install-linux.sh --skip-build  # reuse the existing build/linux-release binary
scripts/install-linux.sh --uninstall   # remove the install and autostart entry
```

KDE Plasma normally provides a StatusNotifier host. GNOME may require an
AppIndicator/StatusNotifier extension; when wxGTK cannot install a tray icon the
program should be launched as a normal dashboard and its configuration remains
usable. Wayland always-on-top is compositor policy and may be ignored; X11 and
KDE generally honour it.

Desktop acceptance targets are Ubuntu 24.04 GNOME (with the Ubuntu AppIndicator
extension enabled) and KDE Plasma 6. On both desktops verify tray icon install,
left-click dashboard activation, the context menu, refresh, settings, exit, and
single-instance activation. If a StatusNotifier host is deliberately absent,
verify that the visible dashboard fallback remains fully usable.

The AppImage CI smoke test runs with `APPIMAGE_EXTRACT_AND_RUN=1`, so it does not
depend on FUSE being available on the runner. It also enforces the 45 MiB package
and 50 MiB RSS-after-60-seconds gates against an isolated, temporary
configuration.

Credentials use the desktop Secret Service through `secret-tool`. If it is not
available or unlocked, the adapter falls back explicitly to memory-only session
storage; those keys cannot be recovered after restart.

## Overlay

Enable the minimal overlay from Settings ("Overlay minimalista" → Habilitar).
It's a small always-on-top window, anchored to a corner (top-right by
default), showing the same compact quota rows as the Windows overlay. Drag it
to reposition; it snaps to the nearest corner on release and remembers its
monitor and corner across restarts. Opacity is configurable from Settings and
brightens on hover.

This first pass deliberately omits the Windows overlay's click-through lock,
global `Ctrl+Alt+U` shortcut, and automatic hiding over full-screen apps —
Wayland has no portable API for global hotkeys or foreground-window
detection, and reimplementing those X11-only would add real complexity for a
first version. Show/hide is available from the tray menu instead.

As with always-on-top generally (see above), GNOME/Wayland compositors may
ignore the overlay's topmost request or lack transparency support; it
degrades to a normal, fully opaque window in that case rather than failing to
appear.

Opacity specifically needs a running compositing manager (X11's Composite
extension is not enough by itself — a compositor must own the
`_NET_WM_CM_S0` selection). Some window managers disable their built-in
compositor when they can't get GPU-accelerated GL, even though software
compositing would work fine: xfwm4 does this and logs `Unsupported GL
renderer` in `~/.xsession-errors` when it declines (seen on remote/virtual
desktops using Mesa's software `llvmpipe` renderer, e.g. over xrdp with no
GPU passthrough). If that happens, a lightweight standalone compositor
running the XRender backend (no GPU required) fixes it without needing to
touch the window manager's own setting:

```sh
sudo apt-get install picom
picom --backend xrender --config /dev/null &
```

The overlay must be re-created after the compositor starts to pick up
transparency (toggle it off and on from Settings, or restart the app) —
`wxTopLevelWindow::SetTransparent()` negotiates the RGBA visual once, before
the window is first shown.

## Verificación del cambio `modernize-desktop-ui` (Linux)

Estado de las gates de release para la modernización de la interfaz,
verificadas en una máquina Linux con sesión XFCE/headless bajo Xvfb:

| Gate | Estado |
|------|--------|
| Build de release con `-Werror` (warnings-as-errors) | ✓ pasa |
| Unit tests (`ai-usage-unit-tests`) | ✓ 13/13 |
| Dashboard wxGTK en tema claro/oscuro bajo fixturas | ✓ capturas light/dark distintas (luminancia media 246 vs 43) |
| AppImage Linux (`AIUsageMonitor-0.2.0-x86_64.AppImage`) | ✓ construido (19,7 MiB) |
| Tamaño del artefacto ≤ 45 MiB | ✓ 19 696 120 bytes |
| RSS ociosa a los 60 s ≤ 50 MiB | ✓ 14 872 KiB |

Quedan **pendientes de entornos no disponibles en esta máquina**:
- Capturas de revisión en **Windows** (lado Windows de la tarea 4.4).
- Build y suite completa en **Windows** (tarea 5.1).
- Smoke checks en escritorios **GNOME/AppIndicator** y **KDE Plasma**
  con host StatusNotifier (tray, tema de escritorio, layout compacto y
  siempre-al-frente) (tarea 5.3).
- Rebuild del **paquete portable de Windows** y sus gates (tarea 5.4).

Estas tareas deberán ejecutarse en un host Windows y en sesiones GNOME/KDE
reales antes de declarar el cambio completo y archivarlo.
