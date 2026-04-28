#!/usr/bin/env python3
"""Evict ROMs unplayed for >N days, turning them back into 0-byte stubs.

Reads play_log.json (written by launch.sh on each launch). For every real
(non-stub) ROM, finds its last-played timestamp and evicts if older than the
threshold. ROMs that have NEVER been played but are non-stub use file mtime
as a fallback (covers manually-placed ROMs).

Usage:
  ./evict.py                # dry-run, show what would be evicted
  ./evict.py --apply        # actually truncate to stubs
  ./evict.py --days 60 --apply
"""
import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ROMS_DIR = Path.home() / "Emulation" / "ROMs"
PLAY_LOG = ROOT / "play_log.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--apply", action="store_true", help="actually evict (default is dry-run)")
    args = ap.parse_args()

    cutoff = time.time() - args.days * 86400
    log = {}
    if PLAY_LOG.exists():
        try:
            log = json.loads(PLAY_LOG.read_text())
        except Exception:
            print("warning: play_log.json unreadable, using mtime only")

    candidates = []
    for system_dir in sorted(ROMS_DIR.iterdir()):
        if not system_dir.is_dir():
            continue
        sys_name = system_dir.name
        sys_log = log.get(sys_name, {})
        for rom in sorted(system_dir.iterdir()):
            if not rom.is_file() or rom.stat().st_size == 0:
                continue
            last = sys_log.get(rom.name, int(rom.stat().st_mtime))
            if last < cutoff:
                age_days = (time.time() - last) / 86400
                candidates.append((sys_name, rom, age_days, rom.stat().st_size))

    if not candidates:
        print("nothing to evict.")
        return

    total = sum(c[3] for c in candidates)
    print(f"{len(candidates)} ROM(s) older than {args.days} days, freeing {total/1e9:.2f} GB:")
    for sys_name, rom, age, size in candidates:
        print(f"  {sys_name}/{rom.name}  ({age:.0f}d, {size/1e6:.1f} MB)")

    if not args.apply:
        print("\n(dry-run) re-run with --apply to evict.")
        return

    for _, rom, _, _ in candidates:
        with open(rom, "wb"):
            pass
    print(f"\nevicted {len(candidates)} ROM(s).")


if __name__ == "__main__":
    main()
