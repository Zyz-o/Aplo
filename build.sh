#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="$project_dir/build"
app_dir="$build_dir/Aplo.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
swift build --package-path "$project_dir" -c release --arch arm64 --product Aplo
binary_dir=$(swift build --package-path "$project_dir" -c release --arch arm64 --show-bin-path)
cp "$binary_dir/Aplo" "$app_dir/Contents/MacOS/Aplo"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
xcrun swift "$project_dir/Scripts/draw-icon.swift" "$build_dir/AppIcon.iconset" "$project_dir/Assets/IconPhoto.jpg"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/LICENSE" "$project_dir/THIRD_PARTY_NOTICES.md" "$project_dir/CHANGELOG.md" "$app_dir/Contents/Resources/"
source_archive="$app_dir/Contents/Resources/CorrespondingSource.zip"
rm -f "$source_archive"
(
  cd "$project_dir"
  /usr/bin/zip -q -r "$source_archive" Sources Scripts Assets Tests Package.swift Info.plist build.sh test.sh LICENSE THIRD_PARTY_NOTICES.md README.md CHANGELOG.md BRAND_COMPATIBILITY.md LAUNCHNEXT_CONFIG_REVIEW.md
)
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
print "Built: $app_dir"
