#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
mkdir -p "$project_dir/build"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$project_dir/Sources/Vendor/LaunchNextSearch/"*.swift "$project_dir/Sources/IntegratedSearch.swift" \
  "$project_dir/Sources/AppClassifier.swift" "$project_dir/Sources/AppCatalog.swift" "$project_dir/Sources/LayoutStore.swift" "$project_dir/Sources/Localization.swift" "$project_dir/Sources/Preferences.swift" "$project_dir/Sources/LauncherModel.swift" "$project_dir/Tests/CatalogTests.swift" \
  -framework AppKit -o "$project_dir/build/CatalogTests"
"$project_dir/build/CatalogTests"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$project_dir/Sources/Vendor/LaunchNextSearch/"*.swift "$project_dir/Sources/IntegratedSearch.swift" \
  "$project_dir/Sources/AppClassifier.swift" "$project_dir/Sources/AppCatalog.swift" "$project_dir/Sources/LayoutStore.swift" \
  "$project_dir/Sources/Localization.swift" "$project_dir/Sources/Preferences.swift" "$project_dir/Sources/LauncherModel.swift" "$project_dir/Sources/LegacyImporter.swift" "$project_dir/Sources/LegacySources.swift" \
  "$project_dir/Tests/LayoutTests.swift" -framework AppKit -lsqlite3 -o "$project_dir/build/LayoutTests"
"$project_dir/build/LayoutTests"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$project_dir/Sources/Vendor/LaunchNextSearch/"*.swift "$project_dir/Sources/IntegratedSearch.swift" \
  "$project_dir/Sources/AppCatalog.swift" "$project_dir/Tests/SearchTests.swift" \
  -framework AppKit -o "$project_dir/build/SearchTests"
"$project_dir/build/SearchTests"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$project_dir/Sources/Localization.swift" "$project_dir/Sources/Preferences.swift" "$project_dir/Tests/PreferencesTests.swift" \
  -o "$project_dir/build/PreferencesTests"
"$project_dir/build/PreferencesTests"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$project_dir/Sources/Vendor/LaunchNextSearch/"*.swift "$project_dir/Sources/IntegratedSearch.swift" \
  "$project_dir/Sources/AppCatalog.swift" "$project_dir/Sources/AppClassifier.swift" \
  "$project_dir/Sources/LayoutStore.swift" "$project_dir/Sources/Localization.swift" "$project_dir/Sources/Preferences.swift" "$project_dir/Sources/LauncherModel.swift" \
  "$project_dir/Tests/ClassificationTests.swift" -framework AppKit -o "$project_dir/build/ClassificationTests"
"$project_dir/build/ClassificationTests"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$project_dir/Sources/PageMotion.swift" "$project_dir/Tests/PageMotionTests.swift" -o "$project_dir/build/PageMotionTests"
"$project_dir/build/PageMotionTests"
