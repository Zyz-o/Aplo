#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$project_dir/Tests" -p 'test_*.py'
exec swift test --package-path "$project_dir" "$@"
