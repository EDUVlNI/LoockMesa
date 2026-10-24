#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/gergelim-eko.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
for suite in PowerRegression MenuRegression; do
  xcrun swiftc -module-cache-path "$check_dir/modules" LoockMesa/Models/*.swift LoockMesa/Services/*.swift LoockMesa/Components/*.swift LoockMesa/Views/*.swift LoockMesa/Eko/*.swift "Tests/$suite.swift" -o "$check_dir/checks"
  "$check_dir/checks"
done
