# arley4mac

> **A complete retro emulation library on macOS, where unplayed games take 0 bytes.**

Browse thousands of games in ES-DE; the actual ROM only downloads when you press play. Subsequent plays are instant. Games unplayed for 30 days truncate themselves back to 0-byte stubs to keep your disk lean.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-black?logo=apple)
![Apple Silicon: native](https://img.shields.io/badge/Apple%20Silicon-native-success)
![Status: working](https://img.shields.io/badge/status-working-green)

---

## Why

Setting up emulation on macOS usually goes one of three ways:

| Approach | Disk used | Setup time | Pain |
|---|---|---|---|
| Download every ROM upfront | 500GB+ | weekends | needs a NAS |
| Download per-game as you go | as-played | 5min/game | tedious |
| Run a Windows-only equivalent in a VM | a whole VM | hours | not native |
| **arley4mac** | **0 bytes until played** | **one command** | **none** |

You get a **full library in ES-DE on day one** — every box-art-scraped game, every system carousel — and your disk only fills up with games you actually touch.

---

## Demo

```
~ Browse 7000+ games in ES-DE (all 0-byte stubs)
~ Pick "Super Mario World" → press play
  → notification: "Downloading..."
  → 0.4 seconds later: SNES boots, game runs natively on M-series
~ Replay the same game later: instant, no network
~ 30 days unplayed: file truncates back to 0 bytes automatically
```

---

## What's in the box

```
   ┌────────────────────────────────────────────────────────────┐
   │  ES-DE  (frontend, sees a full library of 0-byte stubs)    │
   └─────────────────────────┬──────────────────────────────────┘
                             │ launches via custom command
                             ▼
   ┌────────────────────────────────────────────────────────────┐
   │  tools/launch.sh  <system> <rom_path>                      │
   │  ──────────────────────────────────────                    │
   │  if size == 0:                                             │
   │      url = lookup(manifests/<system>.json, basename(rom))  │
   │      curl url → cache                                      │
   │      if .7z: 7zz extract                                   │
   │      replace stub with real file in place                  │
   │  log play time → play_log.json                             │
   │  exec emulator (RetroArch / Dolphin / PCSX2 / DuckStation /│
   │                 melonDS / Azahar)                          │
   └────────────────────────────────────────────────────────────┘
                             │
                             ▼
                   game window appears.
```

| Console | Emulator | Arch on M-series |
|---|---|---|
| NES, SNES, GB, GBA, N64, Genesis, Dreamcast, Arcade | RetroArch + libretro cores | **native arm64** |
| GameCube + Wii | Dolphin | native arm64 |
| PS2 | PCSX2 | universal |
| DS | melonDS | native arm64 |
| PS1 | DuckStation | universal |
| 3DS | Azahar (Citra fork) | universal |
| Frontend | ES-DE | native arm64 |

The brew cask of RetroArch ships x86_64 only — `install.sh` detects this and replaces it with the official **universal** build from libretro so cores run natively, not under Rosetta.

---

## Install

```bash
git clone https://github.com/CTroya/arley4mac.git
cd arley4mac
./install.sh
```

That's it. The installer:

- Auto-installs Homebrew if it's missing
- Brings in Dolphin, PCSX2, melonDS, ES-DE, sevenzip via brew
- Fetches RetroArch (universal arm64), DuckStation, Azahar manually
- Strips quarantine + ad-hoc signs all libretro cores so Gatekeeper doesn't kill them
- Auto-detects host arch and pulls the matching cores
- Writes an ES-DE override config that routes launches through the on-demand wrapper
- Offers to launch ES-DE for you

Then in ES-DE: set ROM dir to `~/Emulation/ROMs`, and one-time per system pick **"On-Demand"** under *Alternative emulators*.

---

## Wire up sources

**Plug-and-play.** Run `install.sh` and you're done — it'll prompt you for an optional bundle URL. Hit enter to use the bundle shipped with the repo, or paste any URL that returns a bundle.

```bash
~/Emulation/Tools/generate_stubs.py
```

That populates 0-byte stubs for every game in the bundle.

The **tool itself** has no host dependency — `generate_stubs.py` just fetches whatever the bundle tells it and resolves URLs in whatever shape it finds them. If you want a bundle that uses different hosts, edit `~/Emulation/Tools/bundle.json` directly, or set `source_url` in `tools/rom_sources.json` to point at a remote one:

```json
{ "source_url": "https://gist.githubusercontent.com/<you>/<id>/raw/bundle.json" }
```

### Bundle format

```json
{
  "base_url": "https://your-host.example/metadata/",

  "snes":      "snes-romset-id",

  "ps2":       { "id": "ps2-romset-id",
                 "name_filter": ["(USA"], "ext_filter": [".7z"] },

  "wii":       { "url": "https://different-host.example/wii.json",
                 "name_filter": ["(USA"] },

  "homebrew":  { "Cool Game.zip": { "url": "https://example.com/file.zip" } }
}
```

`base_url` is declared **once**. Per-system entries are short — the tool concatenates `base_url + id` to form the full URL it fetches. Want to swap hosts? Change one line.

Per-system value can be:
- **String** → treated as `id`, full URL = `base_url + value`
- **Object with `id`** → `base_url + id`, plus optional `name_filter` / `ext_filter` / `name_exclude` / `subdir_strip` / `dest_subdir`
- **Object with `url`** → absolute URL, ignores `base_url` (useful when one system needs a different host)
- **Object without `id`/`url`** → inline manifest, no fetch

The tool auto-detects whether a fetched response is metadata-style (top-level `files: []` array) or already a flat `{filename: {url, size}}` manifest, and translates if needed.

---

## Disk policy

`tools/evict.py` reads the play log written by `launch.sh` and truncates anything unplayed for >30 days back to 0 bytes:

```bash
~/Emulation/Tools/evict.py                # dry-run
~/Emulation/Tools/evict.py --apply        # do it
~/Emulation/Tools/evict.py --days 60 --apply
```

Run it weekly via cron (`crontab -e`):
```
0 4 * * 0 ~/Emulation/Tools/evict.py --apply >/dev/null 2>&1
```

---

## Layout

```
~/Emulation/
├── ROMs/<system>/        ← stubs + cached real ROMs
├── BIOS/                 ← drop PS1/PS2/3DS BIOS here
├── Saves/                ← central save dir
├── Downloads_cache/      ← transient extraction scratch
└── Tools/
    ├── launch.sh         ← on-demand wrapper called by ES-DE
    ├── generate_stubs.py ← reads rom_sources.json, fetches each URL, writes stubs
    ├── evict.py          ← garbage collector
    ├── fetch_cores.sh    ← libretro cores downloader
    ├── bundle.json       ← system → URL/id mapping (edit freely)
    ├── rom_sources.json  ← optional: source_url to override the local bundle
    ├── manifests/        ← generated: filename → URL per system
    ├── play_log.json     ← generated by launch.sh
    └── uninstall.sh

~/ES-DE/custom_systems/es_systems.xml   ← routes launches through launch.sh
```

---

## BIOS files (still your responsibility)

| System | BIOS needed | Where |
|---|---|---|
| PS1 | scph5500.bin, scph5501.bin, scph5502.bin | `~/Emulation/BIOS/` |
| PS2 | required, dump from your own console | PCSX2 prefs |
| 3DS | aes_keys.txt + Boot9/Boot11 from a real 3DS | Azahar prefs |
| All others | none | — |

---

## Uninstall

```bash
~/Emulation/Tools/uninstall.sh
```

Removes brew packages, manually-installed `.app`s, all `~/Library/...` per-emulator config dirs, `~/ES-DE/`, and `~/Emulation/`. Homebrew itself stays.

---

## What's harder

- **3DS** — most public decrypted 3DS sets are torrent-only. The on-demand path needs HTTP. Add ROMs manually to `~/Emulation/ROMs/3ds/`.
- **Wii** — large ISOs and per-file items are sparse. Manual.
- **Arcade (MAME)** — has its own romset versioning quirks. Use [mame-tools](https://www.mamedev.org/) directly.

---

## How the magic works

A few details that aren't obvious:

- **The client is host-agnostic.** It auto-detects between a metadata-style listing (top-level `files` array) and a plain `{filename: {url}}` manifest. If a host goes away, point `source_url` at a different bundle.
- **Stubs are just empty files** with the real ROM filename. ES-DE doesn't care that they're 0 bytes — its scanner sees `Super Mario World (USA).zip` and adds it to the carousel.
- **The tool prefers metadata JSON over HTML directory listings.** HTML listings are often paginated and incomplete for items with thousands of files — easy bug to fall into.
- **Cores get ad-hoc signed** because libretro buildbot dylibs are unsigned, and macOS Sequoia refuses to load unsigned dylibs into signed apps. `codesign --sign -` gets you past that.
- **`%ROM%` not `%ROMRAW%`** in the ES-DE override — ES-DE escapes spaces with backslashes in `%ROM%`, which is what bash wants when the path is unquoted.
- **The launch script runs in a stripped-down PATH** when invoked by ES-DE, which is why `7zz` and brew binaries need `/opt/homebrew/bin` re-prepended explicitly.

---

## Legal

This tool is plumbing. It ships with no curated ROM URLs: `source_url` is `null` until you point it at a bundle. The bundle determines where ROMs come from. Whether downloading any specific ROM you point this at is legal depends on your jurisdiction and whether you own the original game. The tool exists for preservation and personal-backup contexts. Don't be a dick about it.

---

## License

[MIT](LICENSE) © 2026 Carlos Troya

## Credits

Built on [ES-DE](https://es-de.org/), [RetroArch](https://www.retroarch.com/), [Dolphin](https://dolphin-emu.org/), [PCSX2](https://pcsx2.net/), [DuckStation](https://github.com/stenzek/duckstation), [melonDS](https://melonds.kuribo64.net/), and [Azahar](https://github.com/azahar-emu/azahar).
