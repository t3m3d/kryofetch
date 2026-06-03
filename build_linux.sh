#!/usr/bin/env bash
# build_linux.sh — build kryofetch on Linux (x86_64 / aarch64).
#
# Counterpart to the Windows build path (run.k → kcc.sh → kryofetch.exe).
# Produces a single static syscall-only ELF binary at ./kryofetch — no
# libc, no dynamic linker, no gcc at user-invocation time. Built against
# the Linux native backend in compiler/linux_x86/elf.k.
#
# Usage:
#   ./build_linux.sh                # builds ./kryofetch from run_linux.k
#   ./build_linux.sh --run          # ... then runs it once
#   ./build_linux.sh --run --watch  # ... then runs in re-render-each-second mode
#
# Prereqs (Arch / Debian / Ubuntu / ParrotOS / Void / NixOS):
#   - krypton checkout reachable via $KRYPTON_ROOT (default: ../krypton)
#   - $KRYPTON_ROOT/kcc.sh must work (`./build.sh` in the krypton repo seeds it)
#   - WSL2 if running on Windows; WSL1 may fail on direct-syscall paths
#
# Why no gcc here: kcc.sh auto-bootstraps the elf_host on first --native
# call. After that, every kcc run is pure-Krypton compilation: parse →
# IR → optimize → elf.k → static ELF. End-user invocation never touches
# a C compiler.

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KRYPTON_ROOT="${KRYPTON_ROOT:-$SCRIPT_DIR/../krypton}"

if [[ ! -x "$KRYPTON_ROOT/kcc.sh" ]]; then
    echo "build_linux.sh: cannot find $KRYPTON_ROOT/kcc.sh" >&2
    echo "  Set KRYPTON_ROOT to your krypton checkout, e.g." >&2
    echo "    KRYPTON_ROOT=/path/to/krypton ./build_linux.sh" >&2
    exit 1
fi

SRC="$SCRIPT_DIR/run_linux.k"
OUT="$SCRIPT_DIR/kryofetch"

echo "build_linux.sh: $SRC -> $OUT (via $KRYPTON_ROOT/kcc.sh)"
"$KRYPTON_ROOT/kcc.sh" -o "$OUT" "$SRC"

if [[ ! -x "$OUT" ]]; then
    echo "build_linux.sh: build failed — $OUT not produced" >&2
    exit 1
fi

# Optional run-after-build modes
RUN=0
WATCH_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --run)        RUN=1 ;;
        --watch)      RUN=1; WATCH_ARGS+=(--watch) ;;
        --watch=*)    RUN=1; WATCH_ARGS+=(--watch "${arg#--watch=}") ;;
        *)            WATCH_ARGS+=("$arg") ;;
    esac
done

size=$(stat -c '%s' "$OUT" 2>/dev/null || wc -c <"$OUT")
echo "build_linux.sh: built ${OUT} (${size} bytes, static ELF)"

if [[ $RUN -eq 1 ]]; then
    exec "$OUT" "${WATCH_ARGS[@]}"
fi
