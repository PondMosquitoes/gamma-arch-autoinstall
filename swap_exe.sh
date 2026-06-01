#!/usr/bin/env bash
set -euo pipefail

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING="$STALKER/xray-monolith-staging"
ACTIVE="$STALKER/Anomaly/bin/AnomalyDX11.exe"

printf "Select engine binary to deploy:\n"
printf "  1) MT DX11AVX  — AVX build (default; any AVX-capable CPU)\n"
printf "  2) MT DX11     — non-AVX build (older CPUs without AVX)\n\n"
read -rp "Choice [1/2, default 1]: " _choice

case "${_choice:-1}" in
    2) SRC="$STAGING/mt_DX11.exe";    LABEL="MT DX11 (non-AVX)" ;;
    *) SRC="$STAGING/mt_DX11AVX.exe"; LABEL="MT DX11AVX" ;;
esac

[[ -f "$SRC" ]] || { printf "Binary not found: %s\n" "$SRC" >&2; exit 1; }

cp "$SRC" "$ACTIVE"
printf "Deployed: %s → AnomalyDX11.exe\n" "$LABEL"
printf "Clearing shader cache...\n"
rm -rf "$STALKER/Anomaly/appdata/shaders_cache/r4/"*
printf "Done. Launch via MO2 as normal.\n"
