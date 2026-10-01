#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
clock_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/mesa-clock-checks.XXXXXX")
trap 'rm -rf "$clock_check_dir"' EXIT
xcrun swiftc -module-cache-path "$clock_check_dir/modules" LoockMesa/Models/*.swift LoockMesa/Services/*.swift LoockMesa/Components/*.swift LoockMesa/Views/*.swift Tests/ClockRenderingChecks.swift -o "$clock_check_dir/checks"
"$clock_check_dir/checks" "$clock_check_dir"
