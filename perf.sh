#!/usr/bin/env bash
# perf.sh — STALKER GAMMA performance tuning (Arch Linux)
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' R='\033[1;31m' N='\033[0m'
info() { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()   { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn() { printf "${Y}[!]${N} %s\n" "$*" >&2; }

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Detect hardware ────────────────────────────────────────────────────────────
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)
CPU_THREADS=$(nproc)
CPU_CORES=$(lscpu | awk '/^Core\(s\) per socket:/ {print $4}')
CPU_THREADS_PER_CORE=$(lscpu | awk '/^Thread\(s\) per core:/ {print $4}')
HAS_EPP=0
[[ -f /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference ]] && HAS_EPP=1

GPU_VENDOR="other"
GPU_NAME=""
VRAM_MIB=0
if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null 2>&1; then
    GPU_VENDOR="nvidia"
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs)
    VRAM_MIB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
fi
[[ -z "$GPU_NAME" ]] && \
    GPU_NAME=$(lspci | grep -i 'VGA compatible' | head -1 | sed 's/.*: //' | xargs)
if [[ "${VRAM_MIB:-0}" -eq 0 ]]; then
    for _f in /sys/class/drm/card*/device/mem_info_vram_total; do
        [[ -f "$_f" ]] && VRAM_MIB=$(( $(cat "$_f") / 1024 / 1024 )) && break
    done
fi
if [[ "${VRAM_MIB:-0}" -gt 0 ]]; then
    _vram_target=$(( VRAM_MIB * 7 / 8 ))
    VRAM_CAP=$(( (_vram_target + 306) / 612 * 612 ))
else
    VRAM_CAP=4096
    warn "VRAM detection failed — defaulting maxDeviceMemory to 4096 MiB"
fi

NATIVE_RES=$(xrandr --query 2>/dev/null | awk '/connected primary/ { match($0, /[0-9]+x[0-9]+/, arr); print arr[0]; exit }')
NATIVE_W=$(printf '%s' "$NATIVE_RES" | cut -dx -f1)
NATIVE_H=$(printf '%s' "$NATIVE_RES" | cut -dx -f2)
if [[ -z "$NATIVE_W" || -z "$NATIVE_H" ]]; then
    NATIVE_W=1920; NATIVE_H=1080
    warn "Native resolution detection failed (xrandr unavailable) — defaulting to 1920x1080"
fi

CPU_FLAGS=$(grep -m1 '^flags' /proc/cpuinfo)
HAS_AVX512=0; HAS_AVX2=0; HAS_AVX=0
grep -qw 'avx512f' <<< "$CPU_FLAGS" && HAS_AVX512=1 || true
grep -qw 'avx2'    <<< "$CPU_FLAGS" && HAS_AVX2=1   || true
grep -qw 'avx'     <<< "$CPU_FLAGS" && HAS_AVX=1    || true
AVX_DETECTED="none"
[[ $HAS_AVX    -eq 1 ]] && AVX_DETECTED="AVX"
[[ $HAS_AVX2   -eq 1 ]] && AVX_DETECTED="AVX2"
[[ $HAS_AVX512 -eq 1 ]] && AVX_DETECTED="AVX-512"

info "Detected CPU:     $CPU_MODEL ($CPU_CORES cores, $CPU_THREADS_PER_CORE threads/core)"
info "Detected GPU:     $GPU_NAME"
info "Detected VRAM:    ${VRAM_MIB} MiB"
info "Detected display: ${NATIVE_W}x${NATIVE_H} (primary)"
info "Detected SIMD:    $AVX_DETECTED (highest supported)"

# ── Interactive configuration ──────────────────────────────────────────────────
# When run non-interactively (Steam launch), all prompts are skipped and safe
# defaults are applied automatically. Prompts only appear when run from a terminal.
INTERACTIVE=0
[[ -t 0 ]] && INTERACTIVE=1

# Gamescope: fullscreen/VRR only. On Wayland/Xwayland, exclusive fullscreen
# doesn't exist for Xwayland apps — gamescope adds a compositing layer that
# reintroduces PSO stutters and input lag. Only choose fullscreen if you are
# running gamescope with a real fullscreen setup (e.g. native Wayland client).
_gs_choice=""
if [[ $INTERACTIVE -eq 1 ]]; then
    printf "\n"
    printf "Play mode:\n"
    printf "  1) Windowed   — no gamescope (recommended for Wayland/Xwayland)\n"
    printf "  2) Fullscreen — gamescope (direct scanout, VRR, realtime compositor)\n"
    sleep 1
    read -rp "Choice [1/2, default 1]: " _gs_choice
fi
USE_GAMESCOPE=0
[[ "${_gs_choice:-1}" == "2" ]] && USE_GAMESCOPE=1

# Resolution: sets vid_mode in user.ltx and gamescope window size.
# In windowed mode on Wayland/Xwayland, do NOT use native resolution — a window
# equal to or larger than the desktop breaks Xwayland mouse confinement: the
# cursor exits the game window at an invisible inner border. Use 1920x1080 on
# a 1440p display, or any resolution that leaves the desktop visible around it.
#
# Chosen resolution is saved to .perf_config and re-applied on every Steam launch
# because the game rewrites user.ltx on exit.
PERF_CONFIG="$STALKER/.perf_config"
[[ -f "$PERF_CONFIG" ]] && source "$PERF_CONFIG"

_res_choice=""
if [[ $INTERACTIVE -eq 1 ]]; then
    printf "\n"
    printf "Game resolution:\n"
    printf "  1) 1280x720\n"
    printf "  2) 1920x1080\n"
    printf "  3) 2560x1440\n"
    printf "  4) Native — %sx%s (detected primary display)\n" "$NATIVE_W" "$NATIVE_H"
    printf "  5) Custom\n"
    sleep 1
    read -rp "Choice [1-5, default 4]: " _res_choice
fi
case "${_res_choice:-4}" in
    1) GAME_W=1280;        GAME_H=720 ;;
    2) GAME_W=1920;        GAME_H=1080 ;;
    3) GAME_W=2560;        GAME_H=1440 ;;
    5)
        sleep 1
        read -rp "Width:  " GAME_W
        sleep 1
        read -rp "Height: " GAME_H
        ;;
    *) GAME_W="${GAME_W:-$NATIVE_W}"; GAME_H="${GAME_H:-$NATIVE_H}" ;;
esac
[[ $INTERACTIVE -eq 1 ]] && printf 'GAME_W=%s\nGAME_H=%s\n' "$GAME_W" "$GAME_H" > "$PERF_CONFIG"

# xray-monolith SIMD level — controls which AVX instruction set the engine is
# compiled against. Wider = faster physics/AI/renderer math, but crashes if run
# on hardware that doesn't support it. Pick the highest level your CPU supports.
#
# AVX    (2011+): 256-bit float SIMD. Safest — any modern CPU.
# AVX2   (2013+ Intel Haswell / 2017+ AMD Zen): adds 256-bit integer SIMD.
#         ~10-15% faster in CPU-heavy code. Recommended for most modern hardware.
# AVX-512 (2017+ Intel Skylake-X / 2022+ AMD Zen 4): 512-bit SIMD. Highest
#         throughput; only use if compiling AND running on the same AVX-512 host.
#         May cause thermal throttling on sustained SIMD load (especially Intel).
_avx_choice=""
if [[ $INTERACTIVE -eq 1 ]]; then
    printf "\n"
    printf "xray-monolith SIMD level for compilation:\n"
    printf "  1) AVX    — 2011+ Intel/AMD; safe baseline\n"
    printf "  2) AVX2   — 2013+ Intel / 2017+ AMD Zen; recommended for most hardware\n"
    printf "  3) AVX-512 — 2017+ Intel / 2022+ AMD Zen 4+; highest throughput\n"
    printf "  (your CPU reports: %s)\n" "$AVX_DETECTED"
    sleep 1
    read -rp "Choice [1/2/3, default 2]: " _avx_choice
else
    # Non-interactive: auto-select based on detected CPU capability
    case "$AVX_DETECTED" in
        "AVX-512") _avx_choice=3 ;;
        "AVX2")    _avx_choice=2 ;;
        *)         _avx_choice=1 ;;
    esac
fi
case "${_avx_choice:-2}" in
    1) AVX_TARGET="AdvancedVectorExtensions";    AVX_LABEL="AVX" ;;
    3) AVX_TARGET="AdvancedVectorExtensions512"; AVX_LABEL="AVX-512" ;;
    *) AVX_TARGET="AdvancedVectorExtensions2";   AVX_LABEL="AVX2" ;;
esac

# ── Frame cap ─────────────────────────────────────────────────────────────────
FRAME_CAP=0
if [[ $INTERACTIVE -eq 1 ]]; then
    printf "\n"
    printf "Frame cap:\n"
    printf "  1) 60fps\n"
    printf "  2) 72fps\n"
    printf "  3) 90fps\n"
    printf "  4) 120fps\n"
    printf "  5) Custom\n"
    printf "  6) Unlimited\n"
    sleep 1
    read -rp "Choice [1-6, default 6]: " _cap_choice
    case "${_cap_choice:-6}" in
        1) FRAME_CAP=60 ;;
        2) FRAME_CAP=72 ;;
        3) FRAME_CAP=90 ;;
        4) FRAME_CAP=120 ;;
        5) sleep 1; read -rp "FPS: " FRAME_CAP ;;
        *) FRAME_CAP=0 ;;
    esac
fi

# ── Custom dxgi.maxDeviceMemory ───────────────────────────────────────────────
_vram_custom=0
if [[ $INTERACTIVE -eq 1 ]]; then
    _vram_rec=$(( VRAM_MIB * 4 / 5 ))
    _vram_cur=$(sed -n 's/^dxgi\.maxDeviceMemory *= *//p' "$STALKER/Anomaly/dxvk.conf" 2>/dev/null | tr -d ' \r')
    [[ -z "$_vram_cur" ]] && _vram_cur="not set"
    _vram_cur_label="$_vram_cur"
    [[ "$_vram_cur" != "not set" ]] && _vram_cur_label="${_vram_cur} MiB"
    printf "\n"
    printf "dxgi.maxDeviceMemory — VRAM budget for DXVK (%s (current) | %s MiB (max available))\n" "$_vram_cur_label" "$VRAM_MIB"
    printf "  Recommended: ~80%% of VRAM ≈ %s MiB\n" "$_vram_rec"
    sleep 1
    read -rp "  Custom amount in MiB [Press enter to skip]: " _vram_input
    if [[ -n "${_vram_input:-}" && "${_vram_input}" =~ ^[0-9]+$ ]]; then
        _vram_custom=$_vram_input
    fi
fi

# ── Custom -heap ───────────────────────────────────────────────────────────────
_heap_custom=0
if [[ $INTERACTIVE -eq 1 ]]; then
    _heap_cur=$(grep '^-heap' "$STALKER/Anomaly/commandline.txt" 2>/dev/null | awk '{print $2}' || printf "not set")
    _heap_rec=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 8 ))
    _heap_cur_label="$_heap_cur"
    [[ "$_heap_cur" != "not set" ]] && _heap_cur_label="${_heap_cur} MiB"
    printf "\n"
    printf -- "-heap — X-Ray heap allocator ceiling (%s (current) | %s MiB (max recommended))\n" "$_heap_cur_label" "$_heap_rec"
    printf "  Recommended: over 1024 MiB\n"
    sleep 1
    read -rp "  Custom amount in MiB [Press enter to skip]: " _heap_input
    if [[ -n "${_heap_input:-}" && "${_heap_input}" =~ ^[0-9]+$ ]]; then
        _heap_custom=$_heap_input
    fi
fi

# ── CPU + NVIDIA persistence: privileged tweaks via perf-root.sh ──────────────
info "CPU + NVIDIA persistence: applying privileged tweaks..."
sudo "$STALKER/perf-root.sh"
EPP_NOTE=$( [[ $HAS_EPP -eq 1 ]] && printf " + performance EPP" || printf "" )
ok "CPU ($CPU_THREADS threads): performance governor${EPP_NOTE}"

# ── NVIDIA: prefer max performance (needs display) ────────────────────────────
if [[ "$GPU_VENDOR" == "nvidia" ]]; then
    ok "NVIDIA: persistence mode ON"

    info "NVIDIA: setting prefer-max-performance..."
    DISPLAY="${DISPLAY:-:0}" nvidia-settings -a '[gpu:0]/GpuPowerMizerMode=1' > /dev/null 2>&1 \
        && ok "NVIDIA: GpuPowerMizerMode → 1 (prefer max performance)" \
        || warn "nvidia-settings failed — DISPLAY not set; power mizer unchanged."
else
    warn "Non-NVIDIA GPU ($GPU_NAME) — skipping NVIDIA-specific tuning."
fi

# ── DXVK config ───────────────────────────────────────────────────────────────
# enableAsync        — background PSO compilation; eliminates stutter on new shader combos
#                      at the cost of a one-frame visual artifact on first encounter.
# enableGraphicsPipelineLibrary — NVIDIA VK_EXT_graphics_pipeline_library: compiles vertex/
#                      fragment stages separately so first-encounter cost is microseconds,
#                      not milliseconds. No visual artifact. Supersedes async for NVIDIA.
DXVK_CONF="$STALKER/Anomaly/dxvk.conf"
info "Writing $DXVK_CONF..."
cat > "$DXVK_CONF" << 'EOF'
dxvk.numCompilerThreads = 0
dxgi.maxFrameLatency = 1
dxvk.enableAsync = True
dxvk.enableGraphicsPipelineLibrary = True
EOF
if [[ $_vram_custom -gt 0 ]]; then
    printf 'dxgi.maxDeviceMemory = %s\n' "$_vram_custom" >> "$DXVK_CONF"
    ok "dxvk.conf: maxDeviceMemory → ${_vram_custom} MiB (custom)"
else
    printf 'dxgi.maxDeviceMemory = %s\n' "$VRAM_CAP" >> "$DXVK_CONF"
    ok "dxvk.conf: maxDeviceMemory → ${VRAM_CAP} MiB (auto 7/8)"
fi
if [[ $FRAME_CAP -gt 0 ]]; then
    printf 'dxgi.maxFrameRate = %s\n' "$FRAME_CAP" >> "$DXVK_CONF"
    ok "dxvk.conf written (frame cap: ${FRAME_CAP}fps)"
else
    ok "dxvk.conf written (uncapped)"
fi

# ── commandline.txt: strip debug flag, enforce heap ───────────────────────────
# -dbg enables assertion checks + memory tracking throughout the render loop.
# No reason for it to be on during normal play.
CMDLINE="$STALKER/Anomaly/commandline.txt"
touch "$CMDLINE"
if grep -q '^-dbg$' "$CMDLINE"; then
    sed -i '/^-dbg$/d' "$CMDLINE"
    ok "commandline.txt: removed -dbg (debug mode was on)"
else
    ok "commandline.txt: -dbg not present"
fi
_heap_val=$(( _heap_custom > 0 ? _heap_custom : 1024 ))
sed -i '/^-heap/d' "$CMDLINE"
printf -- '-heap %s\n' "$_heap_val" >> "$CMDLINE"
ok "commandline.txt: -heap ${_heap_val} MiB"

# ── A-Life online simulation radius ───────────────────────────────────────────
# switch_distance: NPCs within this radius are fully simulated (pathfinding,
# Lua callbacks, physics). Beyond it they are abstract — no CPU cost.
# GAMMA default is 450m; 200m cuts ~80% of the simulated area while preserving
# all practical combat ranges. switch_factor is left at whatever the file
# currently has — 1.5 causes an unhandled exception; do not touch it.
# auto_switch_distance_normal must also be 200 — GAMMA's Lua adjuster
# (xr_patch.script) overrides switch_distance at runtime after load; if this
# stays at 450 it silently undoes the switch_distance change after 10 seconds.
# auto_switch_distance_start is left at 1250 intentionally: on load everything
# within 1250m spawns online, then after auto_switch_timer (10s) it pulls back
# to 200. This prevents pop-in on zone entry.
_alife_choice=""
if [[ $INTERACTIVE -eq 1 ]]; then
    printf "\n"
    sleep 1
    read -rp "Apply A-Life patch? (switch_distance 450→200, prevents CPU overrun) [Y/n]: " _alife_choice
fi
ALIFE_LTX="$STALKER/GAMMA/mods/G.A.M.M.A. Alife optimization/gamedata/configs/alife.ltx"
if [[ "${_alife_choice:-Y}" =~ ^[Yy]$ ]]; then
    if [[ -f "$ALIFE_LTX" ]]; then
        info "Patching alife.ltx..."
        sed -i '/^\s*switch_distance\s*=/d' "$ALIFE_LTX"
        printf 'switch_distance = 200\n' >> "$ALIFE_LTX"
        sed -i '/^\s*auto_switch_distance_normal\s*=/d' "$ALIFE_LTX"
        printf 'auto_switch_distance_normal = 200\n' >> "$ALIFE_LTX"
        ok "alife.ltx: switch_distance → 200m | auto_switch_distance_normal → 200m"
    else
        warn "alife.ltx not found at $ALIFE_LTX — skipping A-Life patch"
    fi
else
    ok "A-Life patch skipped."
fi

# ── xray-monolith: set SIMD level in vcxproj files ───────────────────────────
XRAY_SRC="$STALKER/xray-monolith-staging/src/src"
if [[ -d "$XRAY_SRC" ]]; then
    info "xray-monolith: setting $AVX_LABEL on vcxproj files..."
    VCXPROJ_COUNT=$({ grep -rl "EnableEnhancedInstructionSet" "$XRAY_SRC" 2>/dev/null || true; } | wc -l)
    if [[ "$VCXPROJ_COUNT" -gt 0 ]]; then
        find "$XRAY_SRC" -name "*.vcxproj" -print0 | xargs -0 sed -i \
            "s|<EnableEnhancedInstructionSet>AdvancedVectorExtensions[^<]*</EnableEnhancedInstructionSet>|<EnableEnhancedInstructionSet>${AVX_TARGET}</EnableEnhancedInstructionSet>|g"
        ok "xray-monolith: $VCXPROJ_COUNT vcxproj(s) → $AVX_LABEL"
        if [[ "$AVX_TARGET" == "AdvancedVectorExtensions512" ]]; then
            warn "If the engine crashes on launch after recompiling: re-run and choose AVX2."
            warn "Still crashing or on very old hardware: re-run and choose AVX."
        elif [[ "$AVX_TARGET" == "AdvancedVectorExtensions2" ]]; then
            warn "If the engine crashes on launch after recompiling: re-run and choose AVX."
        fi
    else
        warn "xray-monolith: no vcxproj files with EnableEnhancedInstructionSet found"
    fi
else
    warn "xray-monolith source not found at $XRAY_SRC — skipping $AVX_LABEL patch"
fi

# ── xray-monolith: deploy pre-built binary ────────────────────────────────────
# AVX binary covers AVX, AVX2, and AVX-512 — all support the 256-bit float SIMD
# floor the binary is compiled against. Non-AVX binary for CPUs without avx in
# /proc/cpuinfo flags.
ANOMALY_BIN="$STALKER/Anomaly/bin/AnomalyDX11.exe"
XRAY_STAGING="$STALKER/xray-monolith-staging"
if [[ -d "$STALKER/Anomaly/bin" ]]; then
    info "Deploying xray-monolith binary..."
    if [[ $HAS_AVX -eq 1 ]]; then
        BIN_SRC="$XRAY_STAGING/mt_DX11AVX.exe"
        BIN_LABEL="MT DX11AVX"
    else
        BIN_SRC="$XRAY_STAGING/mt_DX11.exe"
        BIN_LABEL="MT DX11 (non-AVX)"
    fi
    if [[ -f "$BIN_SRC" ]]; then
        cp "$BIN_SRC" "$ANOMALY_BIN"
        ok "AnomalyDX11.exe → $BIN_LABEL"
    else
        warn "Binary not found: $BIN_SRC — skipping deployment"
    fi
else
    warn "Anomaly/bin not found — skipping binary deployment"
fi

# ── Optional: gamemode ────────────────────────────────────────────────────────
if ! command -v gamemoderun &>/dev/null; then
    if [[ -t 0 ]]; then
        info "Installing gamemode (optional — enables gamemoderun in launch options)..."
        sudo pacman -S --needed --noconfirm gamemode || warn "gamemode install failed — remove gamemoderun from launch options if the game won't start."
    else
        warn "gamemode not installed — run perf.sh manually once to install it."
    fi
fi

# ── Steam launch options ──────────────────────────────────────────────────────
# gamescope is included here for players who want true fullscreen (direct
# scanout via KWin unredirect, VRR). For windowed play it adds a compositing
# layer that can reintroduce PSO stutters and ~1ms of input lag with no
# offsetting benefit — if you play windowed, remove gamescope from the launch
# option and use the bare gamemoderun line from perf.sh instead.
#
# gamescope flags:
#   -w/-h/-W/-H  set to chosen game resolution
#   --backend wayland       output to desktop Wayland compositor
#   --adaptive-sync         request VRR from KWin (reduces display latency)
#   -f                      fullscreen gamescope window → KWin unredrects →
#                           direct scanout, no compositing on final present
#   --rt                    realtime scheduling for gamescope compositor thread
#   NO --force-windows-fullscreen  crops mouse movement (MO2 must launch first)
#   NO -r                   no frame rate cap
#   NO -e                   --steam is Steam Deck only; hangs on desktop
#   NO --immediate-flips    embedded/DRM mode only, no-op when nested
#   NO -F nis/fsr           upscaling filter adds processing; linear is fine
WINE_TOPO="WINE_CPU_TOPOLOGY=${CPU_CORES}:${CPU_THREADS_PER_CORE}"
GAMESCOPE="gamescope -w ${GAME_W} -h ${GAME_H} -W ${GAME_W} -H ${GAME_H} --backend wayland --adaptive-sync -f --rt --"

# NOTE: DO NOT PROMOTE THIS LINE — Steam pointer is script-specific.
# LAUNCH_SCRIPT always resolves to whichever script is running: perf.sh → perf.sh,
# perf-dev.sh → perf-dev.sh. When promoting content from perf-dev.sh to perf.sh,
# leave LAUNCH_SCRIPT and the LAUNCH_OPTS lines below untouched in both files.
LAUNCH_SCRIPT="$(basename "${BASH_SOURCE[0]}")"

if [[ $USE_GAMESCOPE -eq 1 ]]; then
    if [[ "$GPU_VENDOR" == "nvidia" ]]; then
        LAUNCH_OPTS="bash -c \"${STALKER}/${LAUNCH_SCRIPT}; exec ${GAMESCOPE} gamemoderun DXVK_ASYNC=1 ${WINE_TOPO} PROTON_ENABLE_NVAPI=1 DXVK_FILTER_DEVICE_NAME='${GPU_NAME}' DXVK_LOG_LEVEL=none %command%\""
    else
        LAUNCH_OPTS="bash -c \"${STALKER}/${LAUNCH_SCRIPT}; exec ${GAMESCOPE} gamemoderun DXVK_ASYNC=1 ${WINE_TOPO} DXVK_FILTER_DEVICE_NAME='${GPU_NAME}' DXVK_LOG_LEVEL=none %command%\""
    fi
else
    if [[ "$GPU_VENDOR" == "nvidia" ]]; then
        LAUNCH_OPTS="bash -c \"${STALKER}/${LAUNCH_SCRIPT}; exec gamemoderun DXVK_ASYNC=1 ${WINE_TOPO} PROTON_ENABLE_NVAPI=1 DXVK_FILTER_DEVICE_NAME='${GPU_NAME}' DXVK_LOG_LEVEL=none %command%\""
    else
        LAUNCH_OPTS="bash -c \"${STALKER}/${LAUNCH_SCRIPT}; exec gamemoderun DXVK_ASYNC=1 ${WINE_TOPO} DXVK_FILTER_DEVICE_NAME='${GPU_NAME}' DXVK_LOG_LEVEL=none %command%\""
    fi
fi

LAUNCH_FILE="$STALKER/launch_options.txt"
printf '%s\n' "$LAUNCH_OPTS" > "$LAUNCH_FILE"

ok "Launch option written to $LAUNCH_FILE"
printf "\n"
printf "  Steam → right-click ModOrganizer.exe → Properties → Launch Options → paste contents of launch_options.txt\n"
printf "\n"
if [[ $USE_GAMESCOPE -eq 1 ]]; then
    ok "Gamescope: ON  (fullscreen / VRR mode)"
else
    ok "Gamescope: OFF (windowed mode)"
fi
printf "\n"
printf '\033[1mIf MO2 crashes, click play and try at least 3 times before saying it does not work. Once it loads once, it is good to go.\033[0m\n'
printf "\n"

# ── GC Flush mod: deploy + modlist ────────────────────────────────────────────
GC_MOD_NAME="GC Flush - local"
GC_MOD_SRC="$STALKER/mods/${GC_MOD_NAME}"
GC_MOD_DEST="$STALKER/GAMMA/mods/${GC_MOD_NAME}"
GC_MODLIST="$STALKER/GAMMA/profiles/G.A.M.M.A/modlist.txt"

if [[ -d "$GC_MOD_SRC" ]] && [[ ! -d "$GC_MOD_DEST" ]]; then
    cp -r "$GC_MOD_SRC" "$GC_MOD_DEST"
    ok "GC Flush mod deployed → GAMMA/mods/"
fi

if [[ -f "$GC_MODLIST" ]] && ! grep -qxF "+${GC_MOD_NAME}" "$GC_MODLIST"; then
    sed -i "1a +${GC_MOD_NAME}" "$GC_MODLIST"
    ok "Modlist: +${GC_MOD_NAME} added"
fi

if [[ $INTERACTIVE -eq 1 ]]; then
    printf '\n'
    printf '\033[1m──────────────────────────────────────────────────────\033[0m\n'
    printf '\033[1m  ACTION REQUIRED: Enable "GC Flush - local" in MO2\033[0m\n'
    printf '\033[1m  Open MO2 → find "GC Flush - local" → check the box.\033[0m\n'
    printf '\033[1m  In-game: INSERT = GC flush | HOME = GC + vid_restart\033[0m\n'
    printf '\033[1m──────────────────────────────────────────────────────\033[0m\n'
    printf '\n'
fi

# ── Custom settings prompt (interactive only — not on Steam launch) ────────────
if [[ -t 0 ]] && [[ -x "$STALKER/settings-inject.sh" ]] && [[ -d "$STALKER/settings" ]]; then
    printf '\033[1m──────────────────────────────────────────────────────\033[0m\n'
    printf '\033[1m  Inject Custom Settings? (from settings/)\033[0m\n'
    printf '\033[1m──────────────────────────────────────────────────────\033[0m\n'
    printf "\n"
    [[ -f "$STALKER/settings/user.ltx" ]] && \
        printf "    user.ltx\n"
    [[ -f "$STALKER/settings/mcm/axr_options.ltx" ]] && \
        printf "    mcm/axr_options.ltx\n"
    for _p in "$STALKER/settings/profiles/"/*/; do
        [[ -f "$_p/modlist.txt" ]] && \
            printf "    profiles/%s/modlist.txt\n" "$(basename "$_p")"
    done
    printf "\n"
    sleep 1
    read -rp "Inject? [Y/n]: " _inject_choice
    if [[ "${_inject_choice:-Y}" =~ ^[Yy]$ ]]; then
        bash "$STALKER/settings-inject.sh"
    else
        ok "Skipped — run ./settings-inject.sh manually any time."
    fi
    printf "\n"
fi

# ── X-Ray threading + resolution (user.ltx) ───────────────────────────────────
# Runs after settings-inject.sh so the chosen resolution is never overwritten
# by the injected user.ltx. settings-inject.sh does a full file copy; this
# block re-applies both tweaks on top of whatever was injected.
# r__threaded_path — offloads A* pathfinding to worker threads; safe with GAMMA's scripts.
# mt_level_call / mt_task_manager intentionally left OFF — GAMMA Lua scripts aren't thread-safe.
USER_LTX="$STALKER/Anomaly/appdata/user.ltx"
if [[ -f "$USER_LTX" ]]; then
    info "Patching user.ltx..."
    sed -i '/^r__threaded_path/d' "$USER_LTX"
    printf 'r__threaded_path on\n' >> "$USER_LTX"
    ok "user.ltx: r__threaded_path on"
    sed -i '/^lua_gcstep/d' "$USER_LTX"
    printf 'lua_gcstep 35\n' >> "$USER_LTX"
    sed -i '/^lua_parallel_gcstep/d' "$USER_LTX"
    printf 'lua_parallel_gcstep 75\n' >> "$USER_LTX"
    sed -i '/^lua_parallel_gc_call_amount/d' "$USER_LTX"
    printf 'lua_parallel_gc_call_amount 37\n' >> "$USER_LTX"
    ok "user.ltx: lua_gcstep 35 | lua_parallel_gcstep 75 | lua_parallel_gc_call_amount 37"
    sed -i '/^vid_mode/d' "$USER_LTX"
    printf 'vid_mode %sx%s\n' "$GAME_W" "$GAME_H" >> "$USER_LTX"
    ok "user.ltx: vid_mode → ${GAME_W}x${GAME_H}"
    # Reduce detail-object (grass) draw calls to shrink render-thread sort arrays.
    # r__detail_density 1.0 at radius 50 floods the detail sort pass and thrashes
    # L1/L2 cache on the single render thread. 0.5 density + 40m radius cuts the
    # visible draw call count by ~68% while still visibly rendering grass.
    sed -i '/^r__detail_density/d' "$USER_LTX"
    printf 'r__detail_density 0.5\n' >> "$USER_LTX"
    sed -i '/^r__detail_height/d' "$USER_LTX"
    printf 'r__detail_height 0.5\n' >> "$USER_LTX"
    sed -i '/^r__detail_radius/d' "$USER_LTX"
    printf 'r__detail_radius 40\n' >> "$USER_LTX"
    ok "user.ltx: r__detail_density 0.5 | r__detail_height 0.5 | r__detail_radius 40 (render sort cache pressure)"
else
    warn "user.ltx not found at $USER_LTX — launch the game once first, then re-run."
fi
