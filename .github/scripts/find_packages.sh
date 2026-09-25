#!/usr/bin/env bash
# Prints GitHub step outputs describing which projects exist.
# Packages that are not there yet are simply left out.
set -euo pipefail
cd "$(dirname "$0")/../.."

packages=()
for dir in packages/* server/auth server/wallet server; do
  if [ -f "$dir/pubspec.yaml" ]; then packages+=("$dir"); fi
done

json="["
for p in "${packages[@]}"; do json+="\"$p\","; done
json="${json%,}]"

echo "dart_packages=$json"
if [ "${#packages[@]}" -gt 0 ]; then echo "has_dart=true"; else echo "has_dart=false"; fi
if [ -f apps/mobile/pubspec.yaml ]; then echo "has_mobile=true"; else echo "has_mobile=false"; fi
