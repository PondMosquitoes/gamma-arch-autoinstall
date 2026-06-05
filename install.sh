#!/usr/bin/env bash
# install.sh — STALKER GAMMA installer for Arch Linux
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' R='\033[1;31m' N='\033[0m'
info()  { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()    { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn()  { printf "${Y}[!]${N} %s\n" "$*" >&2; }
die()   { printf "${R}[✗]${N} %s\n" "$*" >&2; exit 1; }
enter() { printf "${Y}[press Enter when done]${N} " >&2; read -r _; printf '\n' >> "$LOG_FILE" 2>/dev/null || true; }

# ── Directories ────────────────────────────────────────────────────────────────
STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf "Stalker directory [%s]: " "$STALKER"; read -r _tmp
STALKER="${_tmp:-$STALKER}"
[[ -d "$STALKER" ]] || die "Not a directory: $STALKER"
cd "$STALKER"

# ── Logging ────────────────────────────────────────────────────────────────────
LOG_DIR="$STALKER/logs"
mkdir -p "$LOG_DIR"
_log_n=1
while [[ -f "$LOG_DIR/log${_log_n}.txt" ]]; do (( _log_n++ )); done
LOG_FILE="$LOG_DIR/log${_log_n}.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Skip list ─────────────────────────────────────────────────────────────────
# Edit logs/!skipped-mods.txt to control which mods are skipped during install.
# One MO2 modlist folder name per line (e.g. "456- Mod Name - Author").
# Remove a line if the mod's download URL is fixed upstream and you want it installed.
_SKIP_FILE="$LOG_DIR/!skipped-mods.txt"
_last_failed_mod=""

if [[ ! -f "$_SKIP_FILE" ]]; then
    cat > "$_SKIP_FILE" << 'SKIPEOF'
# Mods skipped during gamma-launcher full-install.
# One MO2 modlist folder name per line — e.g.: 456- Mod Name - Author
# Remove a line if the mod's download URL is fixed upstream and you want it installed.
# Skipped mods must be downloaded manually if you want them.
#
# Known broken (expired CDN signed URL, returns empty 7z stub instead of real archive):
456- FDDA Redone Fixes - Kute
SKIPEOF
fi

COMPAT="${COMPAT:-$HOME/.steam/steam/steamapps/compatdata}"
[[ -d "$COMPAT" ]] || COMPAT="$HOME/.local/share/Steam/steamapps/compatdata"
printf "Steam compatdata  [%s]: " "$COMPAT"; read -r _tmp
printf '%s\n' "${_tmp:-}" >> "$LOG_FILE"
COMPAT="${_tmp:-$COMPAT}"
[[ -d "$COMPAT" ]] || die "compatdata not found: $COMPAT\n  Try: ~/.local/share/Steam/steamapps/compatdata"

ID_STORE="$STALKER/.pfx_paths"

mkdir -p "$STALKER/pip-cache" "$STALKER/cache" "$STALKER/Anomaly" "$STALKER/GAMMA"

# ── System packages ────────────────────────────────────────────────────────────
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    die "multilib not enabled — uncomment [multilib] in /etc/pacman.conf, then: sudo pacman -Sy"
fi

PKGS=(python git libunrar winetricks curl)
MISSING=()
for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null || MISSING+=("$p"); done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Installing: ${MISSING[*]}"
    sudo pacman -S --needed --noconfirm "${MISSING[@]}"
fi

if ! command -v protontricks &>/dev/null; then
    info "Installing protontricks..."
    if sudo pacman -S --needed --noconfirm protontricks 2>/dev/null; then
        ok "protontricks installed via pacman."
    elif command -v yay &>/dev/null; then
        yay -S --needed --noconfirm protontricks
        ok "protontricks installed via yay."
    elif command -v paru &>/dev/null; then
        paru -S --needed --noconfirm protontricks
        ok "protontricks installed via paru."
    else
        die "protontricks not found. Install it: yay -S protontricks"
    fi
fi

# ── venv + gamma-launcher ──────────────────────────────────────────────────────
[[ -f gamma/bin/activate ]] || python -m venv gamma
source "$STALKER/gamma/bin/activate"
TMPDIR="$STALKER/pip-cache" pip install -q --upgrade pip setuptools

[[ -d gamma-launcher/.git ]] || git clone https://github.com/Mord3rca/gamma-launcher.git
if ! gamma-launcher --version &>/dev/null 2>&1; then
    (cd gamma-launcher && TMPDIR="$STALKER/pip-cache" pip install -q .)
fi

_gl_venv=$(find "$STALKER/gamma/lib" -name "site-packages" -maxdepth 3 -type d 2>/dev/null | head -1)
python3 "$STALKER/patch-gamma-launcher.py" "$STALKER/gamma-launcher" "${_gl_venv:-}" "$_SKIP_FILE"
ok "gamma-launcher $(gamma-launcher --version 2>&1 | head -1)"

# ── Helpers ────────────────────────────────────────────────────────────────────
_anomaly_ok() {
    [[ -f "$STALKER/Anomaly/AnomalyLauncher.exe" ]] && \
    [[ -f "$STALKER/Anomaly/db/levels/levels.db0" ]] && \
    [[ -f "$STALKER/GAMMA/ModOrganizer.exe" ]]
}

save_id() {
    local key="$1" val="$2"
    grep -v "^${key}=" "$ID_STORE" 2>/dev/null > "${ID_STORE}.tmp" || true
    printf '%s=%s\n' "$key" "$val" >> "${ID_STORE}.tmp"
    mv "${ID_STORE}.tmp" "$ID_STORE"
}

load_id() {
    [[ -f "$ID_STORE" ]] || return 1
    local val
    val=$(grep "^${1}=" "$ID_STORE" 2>/dev/null | cut -d= -f2- || true)
    [[ -n "$val" ]] && printf '%s' "$val" && return 0
    return 1
}

snapshot_compat() { ls "$COMPAT" 2>/dev/null | sort; }

detect_new_id() {
    local before_snap="$1" after_snap new_ids
    after_snap=$(snapshot_compat)
    new_ids=$(comm -13 <(printf '%s' "$before_snap") <(printf '%s' "$after_snap"))
    local count=0
    [[ -n "$new_ids" ]] && count=$(printf '%s\n' $new_ids | grep -c . || true)
    if   [[ "$count" -eq 0 ]]; then return 1
    elif [[ "$count" -gt 1 ]]; then
        warn "Multiple new prefixes detected: $new_ids"
        warn "Delete the extras from Steam and try again."
        return 1
    fi
    printf '%s' "$new_ids"
}

get_or_create_id() {
    local key="$1" name="$2" exe="$3"
    shift 3

    if load_id "$key" >/dev/null 2>&1; then
        local id; id=$(load_id "$key")
        ok "$name: using cached Steam ID $id"
        printf '%s' "$id"
        return
    fi

    local before; before=$(snapshot_compat)

    info "=== Add $name to Steam ==="
    printf "\n" >&2
    printf "  1. Steam > Games > Add a Non-Steam Game > Browse\n" >&2
    printf "     Select: %s\n" "$exe" >&2
    printf "  2. Right-click the new entry > Properties > Compatibility\n" >&2
    printf "     Check 'Force the use of a specific Steam Play compatibility tool'\n" >&2
    printf "     Select Proton 10\n" >&2
    printf "  3. Properties > Launch Options: %%command%%\n" >&2
    while [[ $# -gt 0 ]]; do printf "  %s\n" "$1" >&2; shift; done
    printf "  ─────────────────────────────────────────────────────────\n" >&2

    local steam_id
    while true; do
        printf "${Y}  Launch the game from Steam now, then press Enter:${N} " >&2; read -r _
        steam_id=$(detect_new_id "$before") && break
        warn "No new prefix found — make sure you launched via Steam (not from file manager)."
    done

    save_id "$key" "$steam_id"
    ok "$name Steam ID: $steam_id"
    printf '%s' "$steam_id"
}

inject_deps() {
    local steam_id="$1" label="$2"
    info "Installing Wine dependencies into $label (Steam ID: $steam_id)..."
    warn "SHA hash warnings for vcrun2022 are expected — non-fatal."
    warn "If cmd fails the script will retry without it."
    if ! protontricks "$steam_id" cmd d3dcompiler_47 d3dx10 d3dx11_43 d3dx9 dx8vb quartz vcrun2022; then
        warn "Retrying without 'cmd'..."
        protontricks "$steam_id" d3dcompiler_47 d3dx10 d3dx11_43 d3dx9 dx8vb quartz vcrun2022 || \
            warn "Some verbs may have failed — continuing."
    fi
    ok "Dependencies ready for $label."
}

# ── Menu (shown on re-run when already installed) ─────────────────────────────
_FORCE_INSTALL=0
_UPDATE_ONLY=0
_INSTALL_DONE="$STALKER/.install_done"

if _anomaly_ok && load_id "ID_MO2" >/dev/null 2>&1 && [[ ! -f "$_INSTALL_DONE" ]]; then
    info "Previous install was interrupted — resuming from protontricks + MO2 config."
elif _anomaly_ok && load_id "ID_MO2" >/dev/null 2>&1; then
    printf "\n"
    info "GAMMA is installed. What would you like to do?"
    printf "\n"
    printf "  1) Remove ReShade\n"
    printf "  2) Update GAMMA\n"
    printf "  3) Redo Steam / protontricks steps\n"
    printf "  4) Backup settings\n"
    printf "  5) Restore settings\n"
    printf "  6) Exit\n"
    printf "\n"
    printf "${Y}  Choice [1-6]:${N} "; read -r _choice; printf '%s\n' "${_choice:-}" >> "$LOG_FILE"

    # ── Settings helpers ───────────────────────────────────────────────────────
    _BACKUP_DIR="$STALKER/.settings_backups"

    _backup_settings() {
        local ts; ts=$(date '+%Y-%m-%d_%H-%M-%S')
        local dest="$_BACKUP_DIR/$ts"
        mkdir -p "$dest/appdata" "$dest/profiles"

        # In-game settings: user.ltx + all mod config ltx files
        cp "$STALKER/Anomaly/appdata/"*.ltx "$dest/appdata/" 2>/dev/null || true
        [[ -f "$STALKER/Anomaly/appdata/imgui.ini" ]] && \
            cp "$STALKER/Anomaly/appdata/imgui.ini" "$dest/appdata/" || true

        # MO2 profile settings (mod list, load order, MCM ini)
        for profile_dir in "$STALKER/GAMMA/profiles/"/*/; do
            local pname; pname=$(basename "$profile_dir")
            mkdir -p "$dest/profiles/$pname"
            cp "$profile_dir"*.{txt,ini} "$dest/profiles/$pname/" 2>/dev/null || true
        done

        ok "Settings backed up → $dest"
    }

    _restore_settings() {
        if [[ ! -d "$_BACKUP_DIR" ]] || [[ -z "$(ls -A "$_BACKUP_DIR" 2>/dev/null)" ]]; then
            warn "No backups found in $_BACKUP_DIR"
            return
        fi

        local backups=()
        while IFS= read -r d; do backups+=("$(basename "$d")"); done \
            < <(find "$_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)

        printf "\n  Available backups (newest first):\n"
        local i=1
        for b in "${backups[@]}"; do printf "    %d) %s\n" "$i" "$b"; (( i++ )); done
        printf "\n"
        printf "${Y}  Choose backup [1-%d] or 0 to cancel:${N} " "${#backups[@]}"; read -r _pick

        [[ "$_pick" == "0" ]] && return
        if ! [[ "$_pick" =~ ^[0-9]+$ ]] || (( _pick < 1 || _pick > ${#backups[@]} )); then
            warn "Invalid choice."; return
        fi

        local src="$_BACKUP_DIR/${backups[$(( _pick - 1 ))]}"

        cp "$src/appdata/"*.ltx  "$STALKER/Anomaly/appdata/"  2>/dev/null || true
        [[ -f "$src/appdata/imgui.ini" ]] && \
            cp "$src/appdata/imgui.ini" "$STALKER/Anomaly/appdata/" || true

        for profile_src in "$src/profiles/"/*/; do
            local pname; pname=$(basename "$profile_src")
            local pdest="$STALKER/GAMMA/profiles/$pname"
            [[ -d "$pdest" ]] && cp "$profile_src"*.{txt,ini} "$pdest/" 2>/dev/null || true
        done

        ok "Settings restored from ${backups[$(( _pick - 1 ))]}."
    }

    case "$_choice" in
        1)
            TMPDIR="$STALKER/pip-cache" gamma-launcher remove-reshade --anomaly "$STALKER/Anomaly"
            ok "ReShade removed."
            exit 0
            ;;
        2)
            _FORCE_INSTALL=1
            _UPDATE_ONLY=1
            rm -f "$_INSTALL_DONE"
            ;;
        3)
            rm -f "$ID_STORE"
            warn "Steam ID cleared — will redo Steam and protontricks steps."
            ;;
        4)
            _backup_settings
            exit 0
            ;;
        5)
            _restore_settings
            exit 0
            ;;
        6)
            exit 0
            ;;
        *)
            die "Invalid choice."
            ;;
    esac
fi

# ── GAMMA full-install ─────────────────────────────────────────────────────────
_PROGRESS_LOG="$STALKER/.gamma_install.log"

_on_install_fail() {
    local last_n newest newest_size
    last_n=$(grep -oP '\(\K[0-9]+(?=/[0-9]+\))' "$_PROGRESS_LOG" 2>/dev/null | tail -1 || true)

    if [[ -n "$last_n" && "$last_n" -gt 0 ]]; then
        warn "Failed at mod ${last_n} — removing partial download from cache."
        newest=$(find "$STALKER/cache" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null \
                 | sort -n | tail -1 | cut -d' ' -f2-)
        if [[ -n "$newest" ]]; then
            newest_size=$(stat -c%s "$newest" 2>/dev/null || echo 0)
            warn "Removed: $(basename "$newest")"
            rm -f "$newest"
        fi

        if [[ "$last_n" == "$_last_failed_mod" ]]; then
            # Same mod failed twice — retrying is pointless, offer to skip it
            local mod_title modlist_name
            mod_title=$(grep -oP '\[\+\] Processing mod \K[^(]+' "$_PROGRESS_LOG" 2>/dev/null \
                        | tail -1 | sed 's/[[:space:]]*$//')
            local _mpack="$STALKER/GAMMA/.Grok's Modpack Installer/G.A.M.M.A/modpack_data"
            if [[ -n "$mod_title" && -f "$_mpack/modlist.txt" ]]; then
                modlist_name=$(grep -mF "$mod_title" "$_mpack/modlist.txt" 2>/dev/null \
                               | sed 's/^[+-]//' | head -1)
            fi

            printf "\n"
            printf "${R}╔══════════════════════════════════════════════════════╗${N}\n"
            printf "${R}║  ERROR — Infinite Retry Detected                     ║${N}\n"
            printf "${R}╚══════════════════════════════════════════════════════╝${N}\n"
            printf "\n"
            printf "  Mod:    %s\n" "${mod_title:-unknown (mod ${last_n})}"
            printf "  Reason: The mod's download URL is broken — the CDN returns\n"
            printf "          an empty archive stub instead of the actual file.\n"
            printf "          Retrying will never succeed.\n"
            printf "\n"
            if [[ -n "$modlist_name" ]]; then
                printf "  This mod can be skipped and added to the skip list:\n"
                printf "    ${Y}%s${N}\n" "$_SKIP_FILE"
                printf "  Skipped mods are NOT installed — download manually from\n"
                printf "  ModDB later if you want them. Remove the entry from\n"
                printf "  !skipped-mods.txt if the URL is ever fixed upstream.\n"
            else
                printf "  Could not resolve modlist name for '${mod_title}'.\n"
                printf "  Add it manually to: ${Y}%s${N}\n" "$_SKIP_FILE"
                printf "  Format: one MO2 folder name per line (e.g. 456- Mod - Author)\n"
            fi
            printf "\n"

            if [[ -n "$modlist_name" ]]; then
                printf "${Y}  Press Enter to skip '${modlist_name}' and retry.${N}\n"
                printf "${Y}  Ctrl+C to abort.${N} "
                read -r _ || true
                printf '<Enter — skip prompt>\n' >> "$LOG_FILE"

                printf "\n"
                warn "Really skip '${modlist_name}'?"
                warn "It will NOT be installed. Download manually from ModDB if you want it."
                warn "Remove it from !skipped-mods.txt if the URL is fixed upstream."
                printf "\n"
                printf "${Y}  Press Enter again to confirm skip. Ctrl+C to abort.${N} "
                read -r _ || true
                printf '<Enter — confirmed skip>\n' >> "$LOG_FILE"

                grep -qxF "$modlist_name" "$_SKIP_FILE" 2>/dev/null || \
                    printf '%s\n' "$modlist_name" >> "$_SKIP_FILE"
                ok "Skipped: ${modlist_name}"
                ok "Entry written to: $_SKIP_FILE"

                local _venv
                _venv=$(find "$STALKER/gamma/lib" -name "site-packages" -maxdepth 3 -type d 2>/dev/null | head -1)
                python3 "$STALKER/patch-gamma-launcher.py" \
                    "$STALKER/gamma-launcher" "${_venv:-}" "$_SKIP_FILE"

                _last_failed_mod=""
                return
            fi
        fi

        _last_failed_mod="$last_n"
    else
        warn "Install failed before any mods were downloaded."
        _last_failed_mod=""
    fi

    printf "${Y}[Enter to retry, Ctrl+C to abort]${N} " >&2
    read -r _ || true
    printf '<Enter — retry>\n' >> "$LOG_FILE"
}

if _anomaly_ok && [[ $_FORCE_INSTALL -eq 0 ]]; then
    ok "GAMMA already installed — skipping full-install."
else
    info "Running GAMMA full-install (large download, takes a long time)..."
    warn "Disable sleep/screen lock before walking away."
    until TMPDIR="$STALKER/pip-cache" \
          gamma-launcher full-install \
              --anomaly           "$STALKER/Anomaly" \
              --gamma             "$STALKER/GAMMA" \
              --cache-directory   "$STALKER/cache" 2>&1 | tee "$_PROGRESS_LOG"; do
        _on_install_fail
    done
    rm -f "$_PROGRESS_LOG"
    TMPDIR="$STALKER/pip-cache" gamma-launcher remove-reshade    --anomaly "$STALKER/Anomaly" || true
    TMPDIR="$STALKER/pip-cache" gamma-launcher purge-shader-cache --anomaly "$STALKER/Anomaly" || true
    ok "GAMMA install complete."
fi

_anomaly_ok || die "Install appears incomplete — re-run the script to retry."
ok "Anomaly + GAMMA verified."

if [[ $_UPDATE_ONLY -eq 1 ]]; then
    ok "GAMMA updated."
    exit 0
fi

# ── ModOrganizer.exe ───────────────────────────────────────────────────────────
warn "MO2 startup errors and visual glitches are normal — ignore them."
MO2_ID=$(get_or_create_id \
    "ID_MO2" \
    "ModOrganizer.exe" \
    "$STALKER/GAMMA/ModOrganizer.exe" \
    "4. Launch MO2 from Steam — Proton will create the prefix." \
    "   If the MO2 setup wizard appears, cancel it and quit MO2." \
    "   (Full MO2 configuration happens after dependencies install.)" \
)

inject_deps "$MO2_ID" "ModOrganizer"

info "Configure MO2:"
printf "  1. Launch ModOrganizer.exe from Steam\n" >&2
printf "  2. Setup wizard: choose 'Create a portable instance'\n" >&2
printf "  3. Game location: browse to the Anomaly folder:\n" >&2
printf "       %s/Anomaly\n" "$STALKER" >&2
printf "     MO2 will auto-prompt for Instance Directory — set it to:\n" >&2
printf "       %s/GAMMA\n" "$STALKER" >&2
printf "  4. Accept defaults for remaining folders > decline tutorial > ignore errors\n" >&2
printf "  5. Close MO2 completely\n" >&2
enter
ok "MO2 configured."

info "Verify GAMMA (DX11):"
printf "  1. Launch ModOrganizer.exe from Steam\n" >&2
printf "  2. In MO2's right pane, select 'Anomaly DX11' from the Executables dropdown\n" >&2
printf "  3. Click Run > New Game > let it load > close\n" >&2
printf "\n" >&2
printf "\033[1m  IF THE GAME CRASHES — IGNORE IT. RE-LAUNCH AND CLICK NEW GAME.\033[0m\n" >&2
printf "\033[1m  YOU SHOULD GET 2 ERRORS AND A CTD. THIS IS NORMAL UPON MAJOR\033[0m\n" >&2
printf "\033[1m  SETTINGS CHANGES (unless you have a monster PC with lots of RAM).\033[0m\n" >&2
printf "\n" >&2
enter
ok "STALKER GAMMA — DX11 verified."

# ── Performance tuning ────────────────────────────────────────────────────────
SUDOERS_FILE="/etc/sudoers.d/stalker-perf"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    info "Configuring perf.sh sudoers (allows CPU/NVIDIA tuning without password prompt)..."
    printf '%s ALL=(root) NOPASSWD: %s/perf-root.sh\n' "$USER" "$STALKER" | \
        sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    ok "sudoers → $SUDOERS_FILE"
fi

[[ -x "$STALKER/perf.sh" ]] && bash "$STALKER/perf.sh"

# ── Custom settings injection ──────────────────────────────────────────────────
if [[ -x "$STALKER/settings-inject.sh" ]] && [[ -d "$STALKER/settings" ]]; then
    info "Injecting custom settings (graphics, MCM, modlist)..."
    bash "$STALKER/settings-inject.sh"
fi

touch "$_INSTALL_DONE"
printf "\n"
ok "Setup complete."
printf "\n"
printf "  GAMMA:            launch ModOrganizer.exe from Steam\n"
printf "                    select renderer in MO2's right-pane dropdown > Run\n"
printf "  Re-run script:    %s/install.sh\n" "$STALKER"
