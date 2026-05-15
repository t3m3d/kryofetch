#!/bin/bash
set -e

VERSION="${1:-1.0.0}"
OUT="release/kryofetch-${VERSION}-macos-arm64.tar.gz"

mkdir -p release

echo "Building kryofetch ${VERSION} for macOS arm64..."
/usr/local/krypton/kcc.sh --gcc run_macos.k -o release/kryofetch 2>&1 | grep -v "^kcc: warning"

echo "Signing..."
codesign -s - -f release/kryofetch

echo "Creating tarball..."
tar -czf "$OUT" -C release kryofetch

echo "SHA256:"
shasum -a 256 "$OUT"

echo ""
echo "Done: $OUT"
echo "Upload to: https://github.com/t3m3d/kryofetch/releases/tag/v${VERSION}"
