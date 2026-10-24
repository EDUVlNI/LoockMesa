#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
clock_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/mesa-clock-checks.XXXXXX")
trap 'rm -rf "$clock_check_dir"' EXIT
xcrun swiftc -module-cache-path "$clock_check_dir/modules" LoockMesa/Models/*.swift LoockMesa/Services/*.swift LoockMesa/Components/*.swift LoockMesa/Views/*.swift LoockMesa/Eko/*.swift Tests/ClockRenderingChecks.swift -o "$clock_check_dir/checks"
mkdir -p dist/previews
if ! "$clock_check_dir/checks" "$PWD/dist/previews"; then
  for report in "$HOME"/Library/Logs/DiagnosticReports/checks*.ips; do
    if [ -f "$report" ]; then head -c 18000 "$report"; fi
  done
  exit 1
fi
