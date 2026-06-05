The project is pretty shitty but it installs gamma. If you don't like performance, fix it yourself. Anyone can fork. Original ver. stays as a reference.

---

# STALKER GAMMA — Arch Linux

Scripts to install and tune STALKER GAMMA on Arch Linux via Steam + Proton.

Clone wherever you want the game to live — `Anomaly/` and `GAMMA/` are created in the same directory as the scripts.

## Before you start

**Install these manually first — the scripts will not install them for you:**

| Package | How |
|---------|-----|
| Arch Linux with `[multilib]` enabled | Uncomment `[multilib]` in `/etc/pacman.conf`, then `sudo pacman -Sy` |
| Steam (native, **not Flatpak**) | `sudo pacman -S steam` — Flatpak Steam is not supported |
| Proton 10 | Steam → Settings → Compatibility → enable Steam Play for all titles, or install "Proton 10" from the Tools library |
| `xorg-xrandr` | `sudo pacman -S xorg-xrandr` — needed for resolution detection; falls back to 1920×1080 if missing |
| `gamescope` *(optional)* | `sudo pacman -S gamescope` — only needed for fullscreen/VRR mode; windowed play works without it |
| `nvidia-utils` *(NVIDIA only)* | `sudo pacman -S nvidia-utils` — needed for `nvidia-smi` and `nvidia-settings` power tuning |
| ~250 GB free disk space | The GAMMA mod download alone is ~100 GB; Anomaly + mods expand further on disk |

**Installed automatically by the scripts:**

- `python`, `git`, `libunrar`, `winetricks`, `curl` — via pacman
- `protontricks` — via pacman, then yay/paru if not in official repos (AUR helper required as fallback)
- `gamemode` — installed by `perf.sh` if not present
- `gamma-launcher` — Python tool, installed into a local venv inside the repo directory

## Install

```bash
git clone <repo> ~/wherever
cd ~/wherever
./autoinstall.sh
```

## Scripts

| Script | What |
|--------|------|
| `autoinstall.sh` | Start here |
| `install.sh` | Downloads Anomaly + GAMMA (~100 GB), sets up MO2 |
| `perf.sh` | CPU/GPU tuning, DXVK, A-Life patch, launch options — runs on every Steam launch |
| `perf-root.sh` | Privileged helper for perf.sh — do not run directly |
| `settings-grab.sh` | Snapshot current settings → `settings/` |
| `settings-inject.sh` | Restore `settings/` → game |
| `swap_exe.sh` | Select which engine binary is deployed |

## Notes

- MO2 crashes on first launch — retry up to 3 times; once it loads once it is stable
- Run `perf.sh` manually before first play; it runs non-interactively on every subsequent Steam launch
- `settings/` contains the author's settings — inject with `./settings-inject.sh`; skip if you prefer defaults
- After `perf.sh` runs, paste `launch_options.txt` into Steam: right-click ModOrganizer.exe → Properties → Launch Options
