#!/usr/bin/env bash
set -euo pipefail

build_dir="${1:-build/linux-release}"
output_dir="${2:-dist}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
appdir="$root/$output_dir/AIUsageMonitor.AppDir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/512x512/apps" "$root/$output_dir"
install -m755 "$root/$build_dir/ai-usage-monitor" "$appdir/usr/bin/ai-usage-monitor"
install -m755 "$root/packaging/linux/AppRun" "$appdir/AppRun"
install -m644 "$root/packaging/linux/ai-usage-monitor.desktop" "$appdir/ai-usage-monitor.desktop"
install -m644 "$root/packaging/linux/ai-usage-monitor.desktop" "$appdir/usr/share/applications/ai-usage-monitor.desktop"
install -m644 "$root/packaging/linux/ai-usage-monitor.png" "$appdir/ai-usage-monitor.png"
install -m644 "$root/packaging/linux/ai-usage-monitor.png" "$appdir/usr/share/icons/hicolor/512x512/apps/ai-usage-monitor.png"

desktop_icon="$(sed -n 's/^Icon=//p' "$appdir/ai-usage-monitor.desktop")"
test "$desktop_icon" = "ai-usage-monitor"
cmp -s "$appdir/ai-usage-monitor.png" "$appdir/usr/share/icons/hicolor/512x512/apps/ai-usage-monitor.png"

linuxdeploy="${LINUXDEPLOY:-linuxdeploy-x86_64.AppImage}"
appimagetool="${APPIMAGETOOL:-appimagetool-x86_64.AppImage}"
"$linuxdeploy" --appdir "$appdir" --executable "$appdir/usr/bin/ai-usage-monitor" --desktop-file "$appdir/ai-usage-monitor.desktop" --icon-file "$appdir/ai-usage-monitor.png"
ARCH=x86_64 "$appimagetool" "$appdir" "$root/$output_dir/AIUsageMonitor-0.2.0-x86_64.AppImage"
sha256sum "$root/$output_dir/AIUsageMonitor-0.2.0-x86_64.AppImage" > "$root/$output_dir/AIUsageMonitor-0.2.0-x86_64.AppImage.sha256"
