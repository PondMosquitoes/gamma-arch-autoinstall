#!/usr/bin/env bash
# settings-grab.sh — snapshot current STALKER GAMMA settings into settings/
#
# Rotation: only two slots are kept.
#   settings/         — current (most recent grab)
#   settings-backup/  — previous grab
#
# Each new grab: old settings/ → settings-backup/ (replacing it), new grab → settings/.
# On the 3rd+ grab the oldest slot is simply deleted.
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' N='\033[0m'
info() { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()   { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn() { printf "${Y}[!]${N} %s\n" "$*" >&2; }

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$STALKER/settings"
BACKUP="$STALKER/settings-backup"

# ── Rotate: current → backup before overwriting ───────────────────────────────
if [[ -d "$SETTINGS" ]]; then
    info "Rotating: settings/ → settings-backup/ (previous backup deleted if present)..."
    rm -rf "$BACKUP"
    mv "$SETTINGS" "$BACKUP"
    ok "Previous settings saved → settings-backup/"
fi

mkdir -p "$SETTINGS/mcm" "$SETTINGS/profiles"

# ── user.ltx — graphics settings + keybinds (same file, one copy) ────────────
info "Grabbing user.ltx..."
if [[ -f "$STALKER/Anomaly/appdata/user.ltx" ]]; then
    cp "$STALKER/Anomaly/appdata/user.ltx" "$SETTINGS/user.ltx"
    ok "user.ltx → settings/user.ltx"
else
    warn "user.ltx not found — launch the game once first"
fi

# ── MCM settings — discover axr_options.ltx under any MCM values mod ─────────
info "Grabbing MCM settings..."
MCM_SRC=""
for candidate in "$STALKER/GAMMA/mods/"*"MCM values"*/gamedata/configs/axr_options.ltx; do
    [[ -f "$candidate" ]] && MCM_SRC="$candidate" && break
done
if [[ -n "$MCM_SRC" ]]; then
    cp "$MCM_SRC" "$SETTINGS/mcm/axr_options.ltx"
    ok "axr_options.ltx → settings/mcm/axr_options.ltx"
else
    warn "MCM axr_options.ltx not found under GAMMA/mods/ — skipping"
fi

# ── MO2 modlists — all profiles, labeled by profile name ─────────────────────
info "Grabbing MO2 modlists..."
for profile_dir in "$STALKER/GAMMA/profiles"/*/; do
    [[ -d "$profile_dir" ]] || continue
    profile_name="$(basename "$profile_dir")"
    if [[ -f "$profile_dir/modlist.txt" ]]; then
        mkdir -p "$SETTINGS/profiles/$profile_name"
        cp "$profile_dir/modlist.txt" "$SETTINGS/profiles/$profile_name/modlist.txt"
        ok "[$profile_name] modlist.txt → settings/profiles/$profile_name/modlist.txt"
    else
        warn "[$profile_name] no modlist.txt — skipping"
    fi
done

printf "\n"
ok "Snapshot complete → $SETTINGS"
[[ -d "$BACKUP" ]] && printf "  Previous settings preserved → settings-backup/\n"
printf "\n"
