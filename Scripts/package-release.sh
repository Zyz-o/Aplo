#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
if [[ "${1:-}" != "--skip-build" ]]; then
  zsh "$project_dir/build.sh"
fi
app_dir="$project_dir/build/Aplo.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
output_dir="$project_dir/dist"
mkdir -p "$output_dir"
codesign --verify --deep --strict "$app_dir"
archive="$output_dir/Aplo-$version-macOS-arm64.zip"
ditto -c -k --keepParent --norsrc --noextattr "$app_dir" "$archive"
(
  cd "$output_dir"
  shasum -a 256 "${archive:t}" > SHA256SUMS.txt
)
print "Packaged: $archive"
