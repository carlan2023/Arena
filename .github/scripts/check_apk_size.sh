#!/usr/bin/env bash
# Fails when an APK is above the install size target in README section 7.
# Usage: check_apk_size.sh <apk> <max megabytes>
set -euo pipefail
apk="$1"
max_mb="$2"
if [ ! -f "$apk" ]; then
  echo "::error::$apk not found"
  exit 1
fi
bytes=$(stat -c %s "$apk")
max_bytes=$((max_mb * 1024 * 1024))
mb=$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b / 1048576 }')
echo "$(basename "$apk"): $mb MB (limit $max_mb MB)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "| $(basename "$apk") | $mb MB | $max_mb MB |" >> "$GITHUB_STEP_SUMMARY"
fi
if [ "$bytes" -gt "$max_bytes" ]; then
  echo "::error::$(basename "$apk") is $mb MB, above the $max_mb MB target"
  exit 1
fi
