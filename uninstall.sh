#!/usr/bin/env bash
# arley4mac uninstaller.
# Removes brew packages, manually-installed .apps, ~/Emulation, ~/ES-DE,
# and all per-emulator config dirs in ~/Library.
set -euo pipefail

confirm() { read -rp "$1 [y/N] " r; [[ "$r" =~ ^[Yy]$ ]]; }

echo "This will permanently remove:"
echo "  - Homebrew casks: dolphin, pcsx2, melonds, es-de"
echo "  - Homebrew formula: sevenzip"
echo "  - /Applications: RetroArch, Azahar, DuckStation"
echo "  - ~/Emulation/  (ROMs, BIOS, saves, manifests, logs, this script)"
echo "  - ~/ES-DE/     (frontend config, gamelists, themes, custom_systems)"
echo "  - Per-emulator config dirs in ~/Library/{Application Support,Preferences,Caches}"
echo
confirm "Proceed?" || { echo "aborted."; exit 0; }

echo "==> Uninstalling brew packages"
for c in dolphin pcsx2 melonds es-de; do
  brew uninstall --cask "$c" 2>/dev/null || true
done
brew uninstall sevenzip 2>/dev/null || true

echo "==> Removing manually installed apps"
rm -rf /Applications/RetroArch.app /Applications/Azahar.app /Applications/DuckStation.app

echo "==> Removing per-emulator config dirs"
APP_SUPPORT=~/Library/"Application Support"
PREFS=~/Library/Preferences
CACHES=~/Library/Caches

rm -rf "$APP_SUPPORT/RetroArch" "$CACHES/RetroArch" "$PREFS/com.libretro.RetroArch.plist"
rm -rf "$APP_SUPPORT/Dolphin" "$CACHES/Dolphin" "$PREFS/Dolphin.plist"
rm -rf "$APP_SUPPORT/PCSX2" "$CACHES/PCSX2" "$PREFS/net.pcsx2.PCSX2.plist"
rm -rf "$APP_SUPPORT/melonDS" "$CACHES/melonDS" "$PREFS/net.kuribo64.melonDS.plist"
rm -rf "$APP_SUPPORT/ES-DE" "$APP_SUPPORT/EmulationStation" "$PREFS/org.es-de.frontend.plist"
rm -rf "$APP_SUPPORT/DuckStation" "$CACHES/DuckStation" "$PREFS/org.duckstation.DuckStation.plist"
rm -rf "$APP_SUPPORT/Azahar" "$APP_SUPPORT/Citra" "$CACHES/Azahar" "$PREFS/org.azahar-emu.azahar.plist"

echo "==> Removing ~/ES-DE and ~/Emulation"
rm -rf ~/ES-DE ~/Emulation

echo
echo "Done. Homebrew itself was not removed."
