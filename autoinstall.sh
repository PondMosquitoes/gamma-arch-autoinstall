#!/usr/bin/env bash
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' N='\033[0m'
info() { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()   { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn() { printf "${Y}[!]${N} %s\n" "$*" >&2; }

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_installed() {
    [[ -f "$STALKER/Anomaly/AnomalyLauncher.exe" ]] && \
    [[ -f "$STALKER/GAMMA/ModOrganizer.exe" ]] && \
    [[ -f "$STALKER/.install_done" ]]
}

_sudoers_ok() {
    [[ -f /etc/sudoers.d/stalker-perf ]]
}

_setup_sudoers() {
    if _sudoers_ok; then ok "sudoers: already configured"; return; fi
    info "Configuring sudoers for passwordless perf-root.sh..."
    printf '%s\n' "$USER ALL=(root) NOPASSWD: $STALKER/perf-root.sh" \
        | sudo tee /etc/sudoers.d/stalker-perf > /dev/null
    sudo chmod 440 /etc/sudoers.d/stalker-perf
    ok "sudoers: /etc/sudoers.d/stalker-perf written"
}

_banner() {
    printf "\n\033[1m══════════════════════════════════════════\033[0m\n"
    printf "\033[1m  STALKER GAMMA — Setup\033[0m\n"
    printf "\033[1m══════════════════════════════════════════\033[0m\n\n"
}

_full_install() {
    # ── Step 1: GAMMA install ─────────────────────────────────────────────────
    printf "\n\033[1mStep 1/3 — GAMMA Install\033[0m\n"
    printf "  Downloads Anomaly + GAMMA (~100 GB). Installs system packages,\n"
    printf "  sets up the MO2 Steam prefix, and injects Wine/D3D runtimes.\n"
    printf "  This is the long step — leave it running.\n\n"
    read -rp "Run install.sh? [Y/n]: " _p1
    if [[ "${_p1:-Y}" =~ ^[Yy]$ ]]; then
        bash "$STALKER/install.sh"
    else
        warn "Skipped — run ./install.sh manually to install GAMMA."
    fi

    # ── Step 2: performance configuration ────────────────────────────────────
    printf "\n\033[1mStep 2/3 — Performance Configuration\033[0m\n"
    printf "  Applies CPU/GPU tuning, configures DXVK, optionally patches A-Life\n"
    printf "  simulation radius, deploys the correct engine binary for your CPU,\n"
    printf "  and writes the Steam launch option to launch_options.txt.\n"
    printf "  Skip this if you want to run stock GAMMA without any tuning.\n\n"
    read -rp "Run perf.sh? [Y/n]: " _p2
    if [[ "${_p2:-Y}" =~ ^[Yy]$ ]]; then
        bash "$STALKER/perf.sh"
    else
        warn "Skipped — run ./perf.sh manually before playing, or use stock GAMMA."
    fi

    # ── Step 3: sudoers ───────────────────────────────────────────────────────
    printf "\n\033[1mStep 3/3 — Sudoers Setup\033[0m\n"
    printf "  Allows perf.sh to set the CPU performance governor and NVIDIA\n"
    printf "  persistence mode without prompting for a password on every launch.\n"
    printf "  Skip this if you skipped perf.sh or don't mind entering your\n"
    printf "  sudo password each session.\n\n"
    read -rp "Configure sudoers? [Y/n]: " _p3
    if [[ "${_p3:-Y}" =~ ^[Yy]$ ]]; then
        _setup_sudoers
    else
        warn "Skipped — sudo password required each launch for perf-root.sh."
    fi

    printf "\n"
    ok "All done."
    [[ -f "$STALKER/launch_options.txt" ]] && \
        printf "  → Copy launch_options.txt to Steam:\n     Steam → right-click ModOrganizer.exe → Properties → Launch Options\n\n"

    read -rp "Open menu? [Y/n]: " _m
    [[ "${_m:-Y}" =~ ^[Yy]$ ]] && _menu
}

_menu() {
    while true; do
        printf "\n\033[1m──────────────────────────────────────────\033[0m\n"
        [[ ! -f "$STALKER/launch_options.txt" ]] && warn "perf.sh not run yet — option 2 recommended."
        _sudoers_ok || warn "sudoers not configured — option 6 recommended."
        printf "  1) Update / reinstall GAMMA\n"
        printf "  2) Reconfigure performance + launch options\n"
        printf "  3) Inject saved settings\n"
        printf "  4) Grab current settings snapshot\n"
        printf "  5) Swap engine binary\n"
        printf "  6) Set up sudoers\n"
        printf "  7) Exit\n\n"
        read -rp "Choice [1-7]: " _c
        printf "\n"
        case "${_c:-7}" in
            1) bash "$STALKER/install.sh" ;;
            2) bash "$STALKER/perf.sh" ;;
            3) bash "$STALKER/settings-inject.sh" || warn "settings-inject.sh exited with an error." ;;
            4) bash "$STALKER/settings-grab.sh"   || warn "settings-grab.sh exited with an error." ;;
            5) bash "$STALKER/swap_exe.sh"         || warn "swap_exe.sh exited with an error." ;;
            6) _setup_sudoers ;;
            7) exit 0 ;;
            *) warn "Invalid choice." ;;
        esac
        printf "\n"
        read -rp "Press Enter to return to menu..." _
    done
}

# ── Entry ─────────────────────────────────────────────────────────────────────
_banner
if _installed; then
    _menu
else
    printf "No GAMMA install detected. Each step will ask before running.\n\n"
    _full_install
fi
