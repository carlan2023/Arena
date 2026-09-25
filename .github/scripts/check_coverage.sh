#!/usr/bin/env bash
# Usage: check_coverage.sh <lcov.info> <minimum percent>
# Fails when line coverage is below the minimum.
set -euo pipefail
file="$1"
min="$2"

if [ ! -f "$file" ]; then
  echo "::error::Coverage file $file not found"
  exit 1
fi

found=$(grep -h '^LF:' "$file" | cut -d: -f2 | awk '{s += $1} END {print s + 0}')
hit=$(grep -h '^LH:' "$file" | cut -d: -f2 | awk '{s += $1} END {print s + 0}')
if [ "$found" -eq 0 ]; then
  echo "No coverable lines yet"
  exit 0
fi
pct=$(( 100 * hit / found ))
echo "Coverage: ${pct} percent of ${found} lines (minimum ${min})"
if [ "$pct" -lt "$min" ]; then
  echo "::error::Coverage ${pct} percent is below ${min} percent"
  exit 1
fi
