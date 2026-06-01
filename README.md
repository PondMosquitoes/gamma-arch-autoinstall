The project is pretty shitty but it installs gamma. If you don't like performance, fix it yourself. Anyone can fork. Original ver. stays as a reference.

---

# STALKER GAMMA — Arch Linux

Scripts to install and tune STALKER GAMMA on Arch Linux via Steam + Proton.

Clone wherever you want the game to live — `Anomaly/` and `GAMMA/` are created in the same directory as the scripts.

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

## Requirements

- Arch Linux with `[multilib]` enabled
- Steam + Proton 10
- ~250 GB free disk space

## Notes

- MO2 crashes on first launch — retry up to 3 times
- Run `perf.sh` manually before first play; it runs non-interactively on every subsequent Steam launch
- `settings/` contains the author's settings — inject with `./settings-inject.sh`; skip if you prefer defaults
- After `perf.sh` runs, paste `launch_options.txt` into Steam: right-click ModOrganizer.exe → Properties → Launch Options
