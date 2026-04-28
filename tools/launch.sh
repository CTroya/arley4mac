#!/usr/bin/env bash
# On-demand ROM launcher. Called by ES-DE with: launch.sh <system> <rom_path>
#
# 1. If rom_path is a 0-byte stub, look up its download URL in the manifest,
#    fetch into ~/Emulation/Downloads_cache/, extract if .7z, and replace the
#    stub with the playable file in-place (or write a sibling .iso/.bin/.cue).
# 2. Update play_log.json with current timestamp.
# 3. Exec the right emulator for the system.
#
# Logs go to ~/Emulation/Tools/launch.log so you can debug from ES-DE.

set -uo pipefail

# ES-DE launches scripts with a minimal PATH; add Homebrew explicitly.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
SEVENZ="/opt/homebrew/bin/7zz"

ROOT="$HOME/Emulation"
TOOLS="$ROOT/Tools"
ROMS="$ROOT/ROMs"
CACHE="$ROOT/Downloads_cache"
LOG="$TOOLS/launch.log"
PLAYLOG="$TOOLS/play_log.json"

mkdir -p "$CACHE"
exec 2>>"$LOG"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') $* ===" >>"$LOG"

if [[ $# -lt 2 ]]; then
  echo "usage: launch.sh <system> <rom_path>" >&2
  osascript -e 'display alert "launch.sh" message "Missing args. Check launch.log."'
  exit 64
fi

SYSTEM="$1"
ROM_PATH="$2"
ROM_NAME="$(basename "$ROM_PATH")"

notify() {
  osascript -e "display notification \"$1\" with title \"Emulation\""
}

# --- 1. resolve stub if needed -----------------------------------------------
if [[ ! -s "$ROM_PATH" ]]; then
  MANIFEST="$TOOLS/manifests/$SYSTEM.json"
  if [[ ! -f "$MANIFEST" ]]; then
    notify "No manifest for $SYSTEM"
    exit 65
  fi

  URL=$(python3 -c "import json,sys; m=json.load(open('$MANIFEST')); e=m.get('''$ROM_NAME'''); print(e['url'] if e else '')")
  if [[ -z "$URL" ]]; then
    notify "No URL for $ROM_NAME"
    exit 66
  fi

  notify "Downloading $ROM_NAME ..."
  echo "fetching $URL" >>"$LOG"

  CACHED="$CACHE/$ROM_NAME"
  if [[ -s "$CACHED" ]]; then
    echo "reusing cached download $CACHED" >>"$LOG"
  else
    if ! curl -fL -A "Mozilla/5.0" -o "$CACHED.part" "$URL" >>"$LOG" 2>&1; then
      notify "Download failed: $ROM_NAME"
      rm -f "$CACHED.part"
      exit 67
    fi
    mv "$CACHED.part" "$CACHED"
  fi

  case "$ROM_NAME" in
    *.7z)
      notify "Extracting $ROM_NAME ..."
      EXTRACT_DIR="$CACHE/_extract_$$"
      mkdir -p "$EXTRACT_DIR"
      if ! "$SEVENZ" x -y -o"$EXTRACT_DIR" "$CACHED" >>"$LOG" 2>&1; then
        notify "Extract failed: $ROM_NAME"
        rm -rf "$EXTRACT_DIR"
        exit 68
      fi
      MAIN_FILE=$(find "$EXTRACT_DIR" -type f \( -name '*.iso' -o -name '*.bin' -o -name '*.cue' -o -name '*.chd' -o -name '*.nds' -o -name '*.gba' -o -name '*.gb' -o -name '*.gbc' -o -name '*.smc' -o -name '*.sfc' -o -name '*.nes' -o -name '*.z64' -o -name '*.n64' -o -name '*.md' -o -name '*.gen' \) | head -1)
      if [[ -z "$MAIN_FILE" ]]; then
        MAIN_FILE=$(find "$EXTRACT_DIR" -type f | head -1)
      fi
      if [[ -z "$MAIN_FILE" ]]; then
        notify "Extract: no usable file found"
        exit 69
      fi
      ROM_DIR="$(dirname "$ROM_PATH")"
      rm -f "$ROM_PATH"
      mv "$EXTRACT_DIR"/* "$ROM_DIR/"
      rm -rf "$EXTRACT_DIR" "$CACHED"
      ROM_PATH="$ROM_DIR/$(basename "$MAIN_FILE")"
      ;;
    *)
      mv "$CACHED" "$ROM_PATH"
      ;;
  esac

  notify "Ready: $(basename "$ROM_PATH")"
fi

# --- 2. update play log -------------------------------------------------------
python3 - "$PLAYLOG" "$SYSTEM" "$(basename "$ROM_PATH")" <<'PY'
import json, sys, time, os
log_path, system, name = sys.argv[1], sys.argv[2], sys.argv[3]
log = {}
if os.path.exists(log_path):
    try: log = json.load(open(log_path))
    except: pass
log.setdefault(system, {})[name] = int(time.time())
with open(log_path, "w") as f:
    json.dump(log, f, indent=2)
PY

# --- 3. dispatch to emulator -------------------------------------------------
RA="/Applications/RetroArch.app/Contents/MacOS/RetroArch"
RA_CORES="$HOME/Library/Application Support/RetroArch/cores"

case "$SYSTEM" in
  nes)        exec "$RA" -L "$RA_CORES/mesen_libretro.dylib" "$ROM_PATH" ;;
  snes)       exec "$RA" -L "$RA_CORES/snes9x_libretro.dylib" "$ROM_PATH" ;;
  gb)         exec "$RA" -L "$RA_CORES/gambatte_libretro.dylib" "$ROM_PATH" ;;
  gba)        exec "$RA" -L "$RA_CORES/mgba_libretro.dylib" "$ROM_PATH" ;;
  n64)        exec "$RA" -L "$RA_CORES/mupen64plus_next_libretro.dylib" "$ROM_PATH" ;;
  megadrive)  exec "$RA" -L "$RA_CORES/genesis_plus_gx_libretro.dylib" "$ROM_PATH" ;;
  dreamcast)  exec "$RA" -L "$RA_CORES/flycast_libretro.dylib" "$ROM_PATH" ;;
  arcade)     exec "$RA" -L "$RA_CORES/fbneo_libretro.dylib" "$ROM_PATH" ;;
  nds)        exec /Applications/melonDS.app/Contents/MacOS/melonDS "$ROM_PATH" ;;
  3ds)        exec /Applications/Azahar.app/Contents/MacOS/azahar "$ROM_PATH" ;;
  psx)        exec /Applications/DuckStation.app/Contents/MacOS/DuckStation -- "$ROM_PATH" ;;
  ps2)        exec /Applications/PCSX2.app/Contents/MacOS/PCSX2 -- "$ROM_PATH" ;;
  gc|wii)     exec /Applications/Dolphin.app/Contents/MacOS/Dolphin -e "$ROM_PATH" ;;
  *)
    notify "Unknown system: $SYSTEM"
    exit 70
    ;;
esac
