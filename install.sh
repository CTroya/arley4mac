#!/usr/bin/env bash
# arley4mac installer.
# Idempotent: re-running is safe and skips work that's already done.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/Emulation"
TOOLS="$ROOT/Tools"
APPS="/Applications"

# ----------------------------------------------------------------------------
# 0. sanity checks
# ----------------------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
  echo "macOS only." >&2; exit 1
fi
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  echo "Unsupported architecture: $ARCH" >&2; exit 1
fi

if ! command -v brew >/dev/null; then
  echo "Homebrew is required but not found."
  yn="y"
  if [[ -t 0 ]]; then
    read -rp "Install it now? (Runs the official installer.) [Y/n] " yn
  fi
  if [[ ! "$yn" =~ ^[Nn] ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    echo "Aborted. Install Homebrew from https://brew.sh and re-run." >&2
    exit 1
  fi
fi

echo "==> Setting up at $ROOT  (arch: $ARCH)"

# ----------------------------------------------------------------------------
# 1. directory tree
# ----------------------------------------------------------------------------
mkdir -p "$ROOT"/{ROMs/{nes,snes,gb,gba,n64,megadrive,nds,3ds,psx,ps2,gc,wii,dreamcast,arcade},BIOS,Saves,Tools,Downloads_cache}

# ----------------------------------------------------------------------------
# 2. brew bundle (Dolphin, PCSX2, melonDS, ES-DE, sevenzip)
# ----------------------------------------------------------------------------
echo "==> brew bundle install"
cp "$REPO_DIR/Brewfile" "$TOOLS/Brewfile"
brew bundle install --file="$TOOLS/Brewfile"

# ----------------------------------------------------------------------------
# 3. RetroArch (universal build — replaces brew's x86_64-only cask if present)
# ----------------------------------------------------------------------------
need_ra=true
if [[ -d "$APPS/RetroArch.app" ]]; then
  ra_bin="$APPS/RetroArch.app/Contents/MacOS/RetroArch"
  if file "$ra_bin" 2>/dev/null | grep -qE "universal|$ARCH"; then
    echo "==> RetroArch already in $APPS (compatible arch). Keeping."
    need_ra=false
  else
    echo "==> Found RetroArch with wrong arch — replacing with universal build"
    brew uninstall --cask retroarch 2>/dev/null || true
    rm -rf "$APPS/RetroArch.app"
    # Wipe cores too — they'll be the wrong arch from the previous install.
    # fetch_cores.sh will repopulate them at the right arch below.
    rm -f "$HOME/Library/Application Support/RetroArch/cores/"*.dylib
  fi
fi
if $need_ra; then
  echo "==> Installing RetroArch (universal libretro build, ~220MB)"
  curl -L -o /tmp/retroarch.dmg \
    "https://buildbot.libretro.com/stable/1.22.2/apple/osx/universal/RetroArch_Metal.dmg"
  hdiutil attach /tmp/retroarch.dmg -nobrowse -quiet
  vol=$(ls /Volumes/ | grep -i retroarch | head -1)
  cp -R "/Volumes/$vol/RetroArch.app" "$APPS/"
  hdiutil detach "/Volumes/$vol" -quiet
  rm -f /tmp/retroarch.dmg
fi

# ----------------------------------------------------------------------------
# 4. Manual app installs: DuckStation (PS1), Azahar (3DS)
#    Uses `find` to locate the .app inside the extracted zip — robust to
#    nesting / version-numbered subdirectories.
# ----------------------------------------------------------------------------
fetch_app() {
  local name="$1" url="$2"
  if [[ -d "$APPS/$name.app" ]]; then
    echo "==> $name already installed"
    return
  fi
  echo "==> Installing $name"
  local tmp="$ROOT/Downloads_cache/$name.zip"
  local unpack="$ROOT/Downloads_cache/_unpack_$name"
  rm -rf "$unpack"
  curl -L -o "$tmp" "$url"
  unzip -q -o "$tmp" -d "$unpack"
  local app_path
  app_path=$(find "$unpack" -maxdepth 4 -type d -name "$name.app" -print -quit)
  if [[ -z "$app_path" ]]; then
    echo "  ! could not find $name.app in extracted archive" >&2
    rm -rf "$unpack" "$tmp"
    return 1
  fi
  mv "$app_path" "$APPS/"
  rm -rf "$unpack" "$tmp"
}

fetch_app "DuckStation" \
  "https://github.com/stenzek/duckstation/releases/download/latest/duckstation-mac-release.zip"

azahar_url=$(curl -sL https://api.github.com/repos/azahar-emu/azahar/releases/latest \
  | python3 -c "import json,sys; d=json.load(sys.stdin); urls=[a['browser_download_url'] for a in d.get('assets', []) if 'macos-universal' in a['name']]; print(urls[0] if urls else '')")
if [[ -n "$azahar_url" ]]; then
  fetch_app "Azahar" "$azahar_url"
else
  echo "  ! could not resolve Azahar download URL — skipping (3DS won't work without manual install)" >&2
fi

# ----------------------------------------------------------------------------
# 5. strip quarantine on emulator apps so script-launches don't get Gatekeepered
# ----------------------------------------------------------------------------
echo "==> Stripping quarantine attributes"
for a in RetroArch Dolphin PCSX2 melonDS DuckStation Azahar; do
  [[ -d "$APPS/$a.app" ]] && xattr -dr com.apple.quarantine "$APPS/$a.app" 2>/dev/null || true
done

# ----------------------------------------------------------------------------
# 6. copy tools into ~/Emulation/Tools
# ----------------------------------------------------------------------------
echo "==> Installing scripts to $TOOLS"
cp "$REPO_DIR/tools/"{launch.sh,generate_stubs.py,evict.py,fetch_cores.sh,rom_sources.json,bundle.json} "$TOOLS/"
cp "$REPO_DIR/uninstall.sh" "$TOOLS/uninstall.sh"
chmod +x "$TOOLS/"{launch.sh,generate_stubs.py,evict.py,fetch_cores.sh,uninstall.sh}

# ----------------------------------------------------------------------------
# 6b. Ask for a bundle URL. Empty input keeps the local bundle.json default.
# ----------------------------------------------------------------------------
if [[ -t 0 ]]; then
  echo
  echo "Bundle URL configures where ROM lookups come from. Leave blank to use"
  echo "the bundle.json shipped with this repo. You can change it later in"
  echo "$TOOLS/rom_sources.json."
  read -rp "Bundle URL (optional): " bundle_url
  if [[ -n "$bundle_url" ]]; then
    python3 -c "
import json, sys
p = '$TOOLS/rom_sources.json'
cfg = json.load(open(p))
cfg['source_url'] = '''$bundle_url'''
json.dump(cfg, open(p, 'w'), indent=2)
print(f'  source_url set to: {cfg[\"source_url\"]}')
"
  else
    echo "  using local bundle.json default"
  fi
fi

# ----------------------------------------------------------------------------
# 7. fetch RetroArch cores (auto-detects arch) and ad-hoc sign them
# ----------------------------------------------------------------------------
echo "==> Fetching RetroArch cores"
"$TOOLS/fetch_cores.sh"

# ----------------------------------------------------------------------------
# 8. generate stubs (no-op until user populates rom_sources.json)
# ----------------------------------------------------------------------------
echo "==> generate_stubs.py (no-op until you configure sources)"
"$TOOLS/generate_stubs.py" || true

# ----------------------------------------------------------------------------
# 9. ES-DE custom_systems config (templated paths)
# ----------------------------------------------------------------------------
es_dir="$HOME/ES-DE/custom_systems"
mkdir -p "$es_dir"
sed "s|__USER_HOME__|$HOME|g" "$REPO_DIR/tools/es_systems.xml.template" \
  > "$es_dir/es_systems.xml"
echo "==> ES-DE override -> $es_dir/es_systems.xml"

# ----------------------------------------------------------------------------
# done
# ----------------------------------------------------------------------------
cat <<EOF

==============================================================
arley4mac is installed.

Next steps:

  1. Generate stubs from the configured bundle:
       ~/Emulation/Tools/generate_stubs.py
       (To change the bundle URL later: edit ~/Emulation/Tools/rom_sources.json)

  2. Open ES-DE → set ROM dir to: $ROOT/ROMs

  3. In each system: menu (Y/Select on controller, F1 on keyboard)
       → Alternative emulators → pick "On-Demand"

  4. Hit play. First launch = download. Subsequent = instant.

Uninstall:  $TOOLS/uninstall.sh
==============================================================
EOF

if [[ -t 0 ]]; then
  read -rp "Launch ES-DE now? [Y/n] " yn
  if [[ ! "$yn" =~ ^[Nn] ]]; then
    open -a ES-DE
  fi
fi
