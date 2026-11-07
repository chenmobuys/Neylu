#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
project_dir="$PWD"
# shellcheck source=scripts/swift-sources.sh
source scripts/swift-sources.sh
app_path="${1:-$project_dir/build/Neylu.app}"
case "$app_path" in /*) ;; *) app_path="$project_dir/$app_path" ;; esac
task_cache="$project_dir/.build/ModuleCache"
iconset_path="$project_dir/.build/Neylu.iconset"
release_version="$(cat VERSION)"
version="${release_version%%-*}"
target_arch="${NEYLU_BUILD_ARCH:-$(uname -m)}"
case "$target_arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $target_arch" >&2; exit 1 ;; esac
build_number="$(cat BUILD_NUMBER)"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[1-9][0-9]*)?$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo 'Invalid BUILD_NUMBER' >&2; exit 1; }
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
[[ "${sdk_version%%.*}" -ge 26 ]] || { echo 'Building requires the macOS 26+ SDK (Xcode 26+).' >&2; exit 1; }
mkdir -p "$task_cache" "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
xcrun swift -module-cache-path "$task_cache" Assets/render-vector-icon.swift Assets/AppIcon-v5-vector.svg "$iconset_path"
iconutil -c icns "$iconset_path" -o "$app_path/Contents/Resources/AppIcon.icns"
python3 Assets/optimize-icon.py "$app_path/Contents/Resources/AppIcon.icns"
xcrun swiftc -module-cache-path "$task_cache" -swift-version 5 -Osize -whole-module-optimization -target "$target_arch-apple-macosx13.0" \
  "${neylu_sources[@]}" Sources/main.swift \
  -o "$app_path/Contents/MacOS/Neylu" -framework AppKit -framework SwiftUI \
  -framework SystemConfiguration -framework ServiceManagement -framework IOKit -framework DiskArbitration -lsqlite3
# Remove debug/local symbol-table entries before signing; keep global symbols
# and Swift/Objective-C runtime metadata intact.
xcrun strip -S -x "$app_path/Contents/MacOS/Neylu"
mkdir -p "$app_path/Contents/Helpers"
xcrun swiftc -module-cache-path "$task_cache" -swift-version 5 -Osize -whole-module-optimization -target "$target_arch-apple-macosx13.0" \
  Sources/Localization.swift Sources/UpdateCore.swift Sources/UpdateMessages.swift Sources/Updater/main.swift -framework AppKit -framework Security \
  -o "$app_path/Contents/Helpers/NeyluUpdater"
xcrun strip -S -x "$app_path/Contents/Helpers/NeyluUpdater"
codesign --force --sign - "$app_path/Contents/Helpers/NeyluUpdater"
cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Neylu</string>
<key>CFBundleIdentifier</key><string>io.github.chenmobuys.Neylu</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Neylu</string>
<key>CFBundleDisplayName</key><string>Neylu</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>NeyluReleaseVersion</key><string>$release_version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
for language in en zh-Hans; do
  mkdir -p "$app_path/Contents/Resources/$language.lproj"
  cp "Resources/$language.lproj/Localizable.strings" "$app_path/Contents/Resources/$language.lproj/"
done
python3 scripts/release.py notes --tag "v$release_version" --file "$app_path/Contents/Resources/ReleaseNotes.md"
cp LICENSE THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
echo "Built: $app_path"
