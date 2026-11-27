#!/usr/bin/env bash
# Builds the Flutter release bundle and packages a distributable archive.
#
# Usage:
#   ./scripts/package-flutter-linux.sh [version]
#
# Output: dist/flutter-linux/<version>/ai-usage-monitor-flutter-linux.tar.gz
set -euo pipefail
cd "$(dirname "$0")/../flutter_app"

version="${1:-0.1.1}"
flutter build linux --release

bundle_dir="build/linux/x64/release/bundle"
dist_dir="../dist/flutter-linux/${version}"
mkdir -p "$dist_dir"
archive_name="ai-usage-monitor-flutter-linux-${version}.tar.gz"

tar -C "$bundle_dir" -czf "$dist_dir/$archive_name" .

echo "packaged: $dist_dir/$archive_name"