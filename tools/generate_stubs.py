#!/usr/bin/env python3
"""Read a bundle, fetch each system's manifest, write 0-byte stubs.

Bundle format:
  {
    "base_url": "<optional URL prefix>",
    "<system>": <entry>,
    ...
  }

<entry> can be:
  - a string id           -> full URL = base_url + id (most concise form)
  - {"id": "...", filters} -> full URL = base_url + id, with optional
                              name_filter / ext_filter / name_exclude /
                              subdir_strip / dest_subdir
  - {"url": "...", filters} -> absolute URL, ignores base_url
                              (use when one system needs a different host)
  - inline dict {filename: {url, size?}} -> used as-is, no fetch

Source of the bundle (in priority order):
  1. tools/rom_sources.json -> source_url   (any HTTP URL or path)
  2. tools/bundle.json next to this script  (default after install)

If a fetched URL returns a JSON object with a top-level 'files' array
(metadata-style listing), it gets auto-translated into manifest form by
swapping '/metadata/' -> '/download/' on the URL and using each file's
'name' to build per-file download links. Other responses are expected to
already be flat {filename: {url, size?}} dicts.

Usage:
  ./generate_stubs.py             # all systems in the bundle
  ./generate_stubs.py snes ps2    # restrict to specific systems
  ./generate_stubs.py --refresh   # recreate stubs that already exist
"""
import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ROMS_DIR = Path.home() / "Emulation" / "ROMs"
CONFIG_PATH = ROOT / "rom_sources.json"
LOCAL_BUNDLE = ROOT / "bundle.json"
MANIFEST_DIR = ROOT / "manifests"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)"

METADATA_URL_RE = re.compile(r"^(https?://[^/]+)/metadata/([^/?#]+)/?$")


def http_get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def passes_filters(name, ext_filter, name_filter, name_exclude):
    if ext_filter and not any(name.lower().endswith(e) for e in ext_filter):
        return False
    if name_filter and not any(s in name for s in name_filter):
        return False
    if name_exclude and any(s in name for s in name_exclude):
        return False
    return True


def metadata_to_manifest(host, item_id, data, subdir_strip):
    """Translate a metadata-style response (top-level 'files' array) into a
    flat {name: {url, size}} manifest. Download URLs are constructed by
    swapping '/metadata/' -> '/download/' on the host."""
    base = f"{host}/download/{item_id}/"
    out = {}
    for f in data.get("files", []):
        full = f.get("name", "")
        if not full:
            continue
        if subdir_strip and full.startswith(subdir_strip):
            display = full[len(subdir_strip):]
        elif "/" in full and not subdir_strip:
            continue
        else:
            display = full
        out[display] = {
            "url": base + urllib.parse.quote(full),
            "size": int(f.get("size", 0)) if f.get("size") else 0,
        }
    return out


def resolve_url(url, subdir_strip):
    data = http_get_json(url)
    m = METADATA_URL_RE.match(url)
    if m and isinstance(data, dict) and isinstance(data.get("files"), list):
        return metadata_to_manifest(m.group(1), m.group(2), data, subdir_strip)
    if not isinstance(data, dict):
        raise ValueError(f"unexpected response from {url}: not a JSON object")
    return data


def resolve_entry(entry, base_url):
    """Return (manifest_dict, filters_dict). filters_dict has the keys
    ext_filter / name_filter / name_exclude / dest_subdir (any may be missing)."""
    # Plain string -> base_url + entry
    if isinstance(entry, str):
        url = (base_url or "") + entry
        return resolve_url(url, ""), {}

    if not isinstance(entry, dict):
        raise ValueError(f"can't interpret entry: {type(entry).__name__}")

    filters = {
        "ext_filter":   [e.lower() for e in entry.get("ext_filter", [])],
        "name_filter":  entry.get("name_filter", []),
        "name_exclude": entry.get("name_exclude", []),
        "dest_subdir":  entry.get("dest_subdir"),
    }
    subdir_strip = entry.get("subdir_strip", "")

    if "id" in entry:
        url = (base_url or "") + entry["id"]
        return resolve_url(url, subdir_strip), filters
    if "url" in entry:
        return resolve_url(entry["url"], subdir_strip), filters
    # Inline manifest, no fetch.
    inline = {k: v for k, v in entry.items()
              if k not in ("ext_filter", "name_filter", "name_exclude",
                           "dest_subdir", "subdir_strip")}
    return inline, filters


def write_stubs_and_manifest(system, manifest, dest_subdir, refresh):
    dest_dir = ROMS_DIR / (dest_subdir or system)
    dest_dir.mkdir(parents=True, exist_ok=True)
    created = 0
    for name in manifest:
        stub = dest_dir / name
        if stub.exists() and stub.stat().st_size > 0 and not refresh:
            continue
        stub.touch()
        created += 1
    MANIFEST_DIR.mkdir(parents=True, exist_ok=True)
    out = MANIFEST_DIR / f"{system}.json"
    out.write_text(json.dumps(manifest, indent=2, sort_keys=True))
    print(f"  {len(manifest)} entries; {created} new stub(s); {out.name}")
    return len(manifest)


def process_system(system, entry, base_url, refresh):
    print(f"\n== {system} ==")
    try:
        manifest, filters = resolve_entry(entry, base_url)
    except Exception as e:
        print(f"  ! resolve failed: {e}")
        return 0

    filtered = {
        n: m for n, m in manifest.items()
        if passes_filters(n, filters["ext_filter"], filters["name_filter"], filters["name_exclude"])
    }
    return write_stubs_and_manifest(system, filtered, filters["dest_subdir"], refresh)


def load_bundle():
    cfg = json.loads(CONFIG_PATH.read_text())
    src = cfg.get("source_url")
    if src:
        print(f"== bundle: {src} ==")
        try:
            return http_get_json(src)
        except Exception as e:
            sys.exit(f"failed to fetch source_url: {e}")

    if not LOCAL_BUNDLE.exists():
        sys.exit(f"no source_url set and {LOCAL_BUNDLE} doesn't exist.")
    print(f"== bundle: {LOCAL_BUNDLE} (local) ==")
    return json.loads(LOCAL_BUNDLE.read_text())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("systems", nargs="*", help="restrict to these systems")
    ap.add_argument("--refresh", action="store_true", help="recreate stubs that already exist")
    args = ap.parse_args()

    bundle = load_bundle()
    if not isinstance(bundle, dict):
        sys.exit("bundle is not a JSON object")

    base_url = bundle.get("base_url", "")
    if base_url:
        print(f"   base_url: {base_url}")

    systems = {k: v for k, v in bundle.items()
               if not k.startswith("_") and k not in ("base_url",)}

    targets = args.systems or list(systems.keys())
    bad = [t for t in targets if t not in systems]
    if bad:
        sys.exit(f"bundle has no entry for: {bad}\navailable: {list(systems.keys())}")

    total = 0
    for system in targets:
        total += process_system(system, systems[system], base_url, args.refresh)

    print(f"\n== summary == {total} entries across {len(targets)} system(s)")


if __name__ == "__main__":
    main()
