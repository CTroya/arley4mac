#!/usr/bin/env bash
# Download RetroArch libretro cores from the official buildbot.
# Auto-detects host arch (arm64 / x86_64). Idempotent: skips installed cores.
set -euo pipefail

ARCH=$(uname -m)
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac
BASE="https://buildbot.libretro.com/nightly/apple/osx/${ARCH}/latest"
CORES_DIR="$HOME/Library/Application Support/RetroArch/cores"
mkdir -p "$CORES_DIR"

CORES=(
  mesen                  # NES
  snes9x                 # SNES
  gambatte               # GB / GBC
  mgba                   # GBA
  mupen64plus_next       # N64
  genesis_plus_gx        # Genesis / Mega Drive
  flycast                # Dreamcast
  fbneo                  # Arcade
)

echo "fetching $ARCH cores from libretro buildbot"
for c in "${CORES[@]}"; do
  if [[ -f "$CORES_DIR/${c}_libretro.dylib" ]]; then
    echo "  have $c, skipping"
    continue
  fi
  echo "  fetching $c..."
  zip="$CORES_DIR/${c}_libretro.dylib.zip"
  if curl -fsL -o "$zip" "$BASE/${c}_libretro.dylib.zip" \
     && unzip -q -o "$zip" -d "$CORES_DIR"; then
    rm -f "$zip"
    dylib="$CORES_DIR/${c}_libretro.dylib"
    xattr -d com.apple.quarantine "$dylib" 2>/dev/null || true
    codesign --force --sign - "$dylib" >/dev/null 2>&1 || true
    echo "    ok"
  else
    rm -f "$zip"
    echo "    FAILED" >&2
  fi
done

echo "done. cores in $CORES_DIR"
