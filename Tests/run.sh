#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/mesa-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -module-cache-path "$check_dir/modules" LoockMesa/Models/*.swift Tests/Checks.swift -o "$check_dir/checks"
"$check_dir/checks"
