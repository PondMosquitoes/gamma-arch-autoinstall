The project is pretty shitty but it installs gamma. If you don't like performance, fix it yourself. Anyone can fork. Original ver. stays as a reference.

---

Read [methodology.md](methodology.md).

`perf.sh` owns `dxvk.conf`, `commandline.txt`, `user.ltx`, `alife.ltx`, and `AnomalyDX11.exe`. All runtime config goes there. `install.sh` is a pure installer — it does not call `perf.sh` or inject settings.

Every prompt in `perf.sh` must be gated on `[[ -t 0 ]]` — the script runs non-interactively on every Steam launch and bare `read` calls will block it silently.

Experiment in `perf-dev.sh` — a scratch copy of `perf.sh` kept out of the repo. Benchmark on Great Swamps — worst-case for CPU. One change at a time. When a change is confirmed good, promote it to `perf.sh` manually. Do NOT commit `perf-dev.sh`.

The mt binaries are byte for byte identical to AOEngine. Apparently. GC & Heap is still the major issue.

## Hard rules

- No `dxvk.conf` changes without testing on **new game start** — several options that work on saves crash X-Ray during world init
- Do not raise `switch_distance` above 200
- Do not touch `switch_factor` in `alife.ltx` — 1.5 causes an unhandled exception
- Do not use community sources as evidence. Test it, measure it
