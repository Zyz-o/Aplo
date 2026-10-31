#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="$project_dir/build"
app_dir="$build_dir/Aplo.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 6 -O -target arm64-apple-macosx13.0 \
  "$project_dir/Sources/Vendor/LaunchNextSearch/"*.swift \
  "$project_dir/Sources/Vendor/LaunchNextSound/"*.swift \
  "$project_dir/Sources/IntegratedSearch.swift" \
  "$project_dir/Sources/AppClassifier.swift" "$project_dir/Sources/AppCatalog.swift" \
  "$project_dir/Sources/LayoutStore.swift" \
  "$project_dir/Sources/LegacyImporter.swift" \
  "$project_dir/Sources/LegacySources.swift" \
  "$project_dir/Sources/PageMotion.swift" "$project_dir/Sources/Localization.swift" "$project_dir/Sources/Preferences.swift" "$project_dir/Sources/LauncherModel.swift" \
  "$project_dir/Sources/ScalePreview.swift" "$project_dir/Sources/SettingsView.swift" \
  "$project_dir/Sources/DockMagnification.swift" "$project_dir/Sources/WindowDragHandle.swift" "$project_dir/Sources/DragHandle.swift" \
  "$project_dir/Sources/LauncherView.swift" \
  "$project_dir/Sources/main.swift" \
  -framework AppKit -framework SwiftUI -framework Carbon -lsqlite3 \
  -o "$app_dir/Contents/MacOS/Aplo"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
xcrun swift "$project_dir/Scripts/draw-icon.swift" "$build_dir/AppIcon.iconset" "$project_dir/Assets/IconPhoto.jpg"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/LICENSE" "$project_dir/THIRD_PARTY_NOTICES.md" "$project_dir/CHANGELOG.md" "$app_dir/Contents/Resources/"
source_archive="$app_dir/Contents/Resources/CorrespondingSource.zip"
rm -f "$source_archive"
(
  cd "$project_dir"
  /usr/bin/zip -q -r "$source_archive" Sources Scripts Assets Tests Info.plist build.sh test.sh LICENSE THIRD_PARTY_NOTICES.md README.md CHANGELOG.md BRAND_COMPATIBILITY.md LAUNCHNEXT_CONFIG_REVIEW.md
)
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
print "Built: $app_dir"
