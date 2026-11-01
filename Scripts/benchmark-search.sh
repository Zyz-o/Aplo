#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
mkdir -p "$project_dir/build"
xcrun swiftc -O -parse-as-library "$project_dir/Sources/AppCatalog.swift" "$project_dir/Sources/IntegratedSearch.swift" "$project_dir"/Sources/Vendor/LaunchNextSearch/*.swift "$project_dir/Scripts/benchmark-search.swift" -o "$project_dir/build/benchmark-search"
exec "$project_dir/build/benchmark-search"
