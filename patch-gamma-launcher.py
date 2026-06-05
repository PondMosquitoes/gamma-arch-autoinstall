#!/usr/bin/env python3
"""
Patch gamma-launcher for broken GAMMA mod downloads.

Usage:
  python3 patch-gamma-launcher.py <gamma-launcher-src-dir> [<venv-site-packages-dir>] [<skip-file>]

Reads the skip-file (one modlist folder name per line) and patches gamma-launcher's
_install_mods() to skip those mods at install time.  Also fixes archive.py so an
empty/corrupt 7z archive (e.g. expired CDN URL returning a stub) raises a clear
error instead of crashing with AttributeError on main_streams.unpackinfo.

Re-run this script any time the skip-file changes — it will update the patch in place.
"""
import re
import sys
from pathlib import Path

# Sentinel lines bracket our dynamic skip block inside install.py.
# patch-gamma-launcher.py uses them to locate and rewrite the block on re-runs.
_SENTINEL_START = '            # GAMMA-ARCH-AUTOINSTALL-SKIP-START'
_SENTINEL_END   = '            # GAMMA-ARCH-AUTOINSTALL-SKIP-END'

# The upstream hardcoded skip that already exists in gamma-launcher — we insert after it.
_UPSTREAM_SKIP = (
    '            if mod.info.name == "164- Hunger Thirst Sleep UI 0.71 - xcvb":\n'
    '                continue\n'
)


def _read_skip_list(skip_file: str) -> list:
    if not skip_file:
        return []
    p = Path(skip_file)
    if not p.exists():
        return []
    return [
        ln.strip() for ln in p.read_text().splitlines()
        if ln.strip() and not ln.startswith('#')
    ]


def _build_skip_block(skips: list) -> str:
    if not skips:
        items = '()'
    elif len(skips) == 1:
        items = f'("{skips[0]}",)'
    else:
        items = '(' + ', '.join(f'"{s}"' for s in skips) + ')'
    return (
        f'{_SENTINEL_START}\n'
        f'            if mod.info.name in {items}:\n'
        f'                continue\n'
        f'{_SENTINEL_END}'
    )


def _patch_install(path: Path, skips: list) -> None:
    if not path.exists():
        return
    txt = path.read_text()
    if _SENTINEL_START in txt:
        new_block = _build_skip_block(skips)
        new_txt = re.sub(
            re.escape(_SENTINEL_START) + r'.*?' + re.escape(_SENTINEL_END),
            new_block,
            txt,
            flags=re.DOTALL,
        )
        if new_txt != txt:
            path.write_text(new_txt)
            print(f'[✓] Updated skip list in {path}')
    elif _UPSTREAM_SKIP in txt:
        new_block = _build_skip_block(skips)
        path.write_text(txt.replace(_UPSTREAM_SKIP, _UPSTREAM_SKIP + new_block + '\n', 1))
        print(f'[✓] Patched skip block into {path}')


def _patch_archive(path: Path) -> None:
    if not path.exists():
        return
    txt = path.read_text()
    old = "        _7zip_bcj2_workaround(f, p) if 'BCJ2*' in archive.archiveinfo().method_names else archive.extractall(p)"
    new = (
        "        try:\n"
        "            method_names = archive.archiveinfo().method_names\n"
        "        except AttributeError:\n"
        "            raise Exception(f'File {f} is empty or corrupt (CDN URL may have expired)')\n"
        "        _7zip_bcj2_workaround(f, p) if 'BCJ2*' in method_names else archive.extractall(p)"
    )
    if old in txt and 'AttributeError' not in txt:
        path.write_text(txt.replace(old, new, 1))
        print(f'[✓] Patched archive error handling in {path}')


def run(gl_dir: str, venv_site: str = None, skip_file: str = None) -> None:
    skips = _read_skip_list(skip_file)
    dirs = [Path(gl_dir)]
    if venv_site:
        dirs.append(Path(venv_site))
    for d in dirs:
        _patch_install(d / 'launcher/commands/install.py', skips)
        _patch_archive(d / 'launcher/archive.py')


if __name__ == '__main__':
    run(
        sys.argv[1],
        sys.argv[2] if len(sys.argv) > 2 else None,
        sys.argv[3] if len(sys.argv) > 3 else None,
    )
