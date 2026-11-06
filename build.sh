#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
project_dir="$PWD"
app_path="${1:-$project_dir/build/Neylu.app}"
case "$app_path" in /*) ;; *) app_path="$project_dir/$app_path" ;; esac
task_cache="$project_dir/.build/ModuleCache"
iconset_path="$project_dir/.build/Neylu.iconset"
version="$(cat VERSION)"
build_number="$(cat BUILD_NUMBER)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo 'Invalid BUILD_NUMBER' >&2; exit 1; }
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
[[ "${sdk_version%%.*}" -ge 26 ]] || { echo 'Building requires the macOS 26+ SDK (Xcode 26+).' >&2; exit 1; }
mkdir -p "$task_cache" "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
xcrun swift -module-cache-path "$task_cache" Assets/render-vector-icon.swift Assets/AppIcon-v5-vector.svg "$iconset_path"
iconutil -c icns "$iconset_path" -o "$app_path/Contents/Resources/AppIcon.icns"
xcrun swiftc -module-cache-path "$task_cache" -swift-version 5 -O -target arm64-apple-macosx13.0 \
  Sources/History.swift Sources/DiskActivity.swift Sources/MiniCharts.swift Sources/Metrics.swift \
  Sources/Temperature.swift Sources/SettingsMenu.swift Sources/Interface.swift Sources/main.swift \
  -o "$app_path/Contents/MacOS/Neylu" -framework AppKit -framework SwiftUI \
  -framework SystemConfiguration -framework ServiceManagement -framework IOKit -framework DiskArbitration -lsqlite3
cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Neylu</string>
<key>CFBundleIdentifier</key><string>local.QuietBar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Neylu</string>
<key>CFBundleDisplayName</key><string>Neylu</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp LICENSE THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
echo "Built: $app_path"
