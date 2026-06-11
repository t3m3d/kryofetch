#!/usr/bin/env bash
# build_macos.sh — build kryofetch for macOS arm64 (pure Krypton, kcc --native).
# Merges the per-area modules into one file first: cross-module calls into
# imported modules misbranch on the native macho backend, so a single module
# keeps every call intra-module (same fix kcode uses).
set -e
cd "$(dirname "$0")"
VERSION="1.2.9"
MERGED="$(mktemp /tmp/kryofetch-merged.XXXX.k)"
{
  grep -v '^import ' utils_macos.k
  for f in cpu_macos os_macos mem_macos disk_macos gpu_macos config_macos run_macos; do
    echo ""; grep -v '^import ' "$f.k"
  done
} > "$MERGED"
mkdir -p release
kcc --native "$MERGED" -o release/kryofetch
codesign -s - -f release/kryofetch
rm -f "$MERGED"
echo "Built: release/kryofetch ($(file -b release/kryofetch))"
