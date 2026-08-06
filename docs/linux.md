# Linux build and tray notes

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
