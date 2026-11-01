#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
exec swift test --package-path "$project_dir" "$@"
