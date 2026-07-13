#!/usr/bin/env bash
#
# Palworld 1.0 dedicated server installer for Debian (12/13). Run as root.
#   sudo ./palworld.sh
#
# Re-running is safe: an existing PalWorldSettings.ini is left untouched.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=lib/serverlib.sh
source "$SCRIPT_DIR/lib/serverlib.sh"

# ─────────────────────────────────────────────────────────────────────────────
#  EDIT THESE
# ─────────────────────────────────────────────────────────────────────────────
SERVER_NAME="My Palworld 1.0 Server"     # name shown to players (avoid " )
SERVER_DESCRIPTION="Palworld dedicated server"
SERVER_PASSWORD=""                        # empty = open server
ADMIN_PASSWORD=""                         # empty = auto-generate a strong one
MAX_PLAYERS=32                            # size to your RAM (16 GB recommended)
GAME_PORT=8211                            # UDP; must be reachable
DISABLE_INVADERS=false                    # true = no raids, less memory-leak pressure

SVC_USER="palworld"
BASE_DIR="/opt/palworld"
# ─────────────────────────────────────────────────────────────────────────────

SERVERLIB_TAG="palworld"
readonly APPID=2394010
STEAMCMD_DIR="$BASE_DIR/steamcmd"
SERVER_DIR="$BASE_DIR/server"
CONFIG_DIR="$SERVER_DIR/Pal/Saved/Config/LinuxServer"
BACKUP_DIR="$BASE_DIR/backups"

serverlib::require_root
serverlib::require_systemd

if [[ -n "$ADMIN_PASSWORD" ]]; then
  ADMIN_GENERATED=false
else
  ADMIN_PASSWORD="$(serverlib::gen_password)"
  ADMIN_GENERATED=true
fi

# ── Install ──────────────────────────────────────────────────────────────────
serverlib::install_base_deps
serverlib::create_service_user "$SVC_USER" "$BASE_DIR"
mkdir -p "$STEAMCMD_DIR" "$SERVER_DIR" "$BACKUP_DIR"
chown -R "$SVC_USER:$SVC_USER" "$BASE_DIR"

serverlib::install_steamcmd "$SVC_USER" "$STEAMCMD_DIR"
serverlib::steam_app_update "$SVC_USER" "$STEAMCMD_DIR" "$SERVER_DIR" "$APPID"
serverlib::link_steamclient "$SVC_USER" "$BASE_DIR" "$STEAMCMD_DIR"

# ── Config (Palworld-specific) ───────────────────────────────────────────────
# Palworld reads a single long OptionSettings=(...) line. Copy the template
# once, then patch in the values above. Existing configs are preserved.
mkdir -p "$CONFIG_DIR"
chown -R "$SVC_USER:$SVC_USER" "$SERVER_DIR/Pal/Saved" 2>/dev/null || true

ini="$CONFIG_DIR/PalWorldSettings.ini"
if [[ -f "$ini" ]]; then
  serverlib::warn "PalWorldSettings.ini exists — leaving it as-is."
else
  [[ -f "$SERVER_DIR/DefaultPalWorldSettings.ini" ]] \
    || serverlib::die "Default config missing — the SteamCMD download did not complete."
  serverlib::log "Writing PalWorldSettings.ini…"
  cp "$SERVER_DIR/DefaultPalWorldSettings.ini" "$ini"
  sed -i "s|ServerName=\"[^\"]*\"|ServerName=\"$(serverlib::sed_escape "$SERVER_NAME")\"|"                 "$ini"
  sed -i "s|ServerDescription=\"[^\"]*\"|ServerDescription=\"$(serverlib::sed_escape "$SERVER_DESCRIPTION")\"|" "$ini"
  sed -i "s|AdminPassword=\"[^\"]*\"|AdminPassword=\"$(serverlib::sed_escape "$ADMIN_PASSWORD")\"|"         "$ini"
  sed -i "s|ServerPassword=\"[^\"]*\"|ServerPassword=\"$(serverlib::sed_escape "$SERVER_PASSWORD")\"|"      "$ini"
  sed -i "s|ServerPlayerMaxNum=[0-9]*|ServerPlayerMaxNum=$MAX_PLAYERS|"                                     "$ini"
  sed -i "s|PublicPort=[0-9]*|PublicPort=$GAME_PORT|"                                                       "$ini"
  if [[ "$DISABLE_INVADERS" == "true" ]]; then
    sed -i "s|bEnableInvaderEnemy=[A-Za-z]*|bEnableInvaderEnemy=False|"                                     "$ini"
  fi
  chown "$SVC_USER:$SVC_USER" "$ini"
fi

# ── Service, helpers, firewall ───────────────────────────────────────────────
serverlib::install_systemd_service \
  "palworld" "Palworld Dedicated Server" "$SVC_USER" "$SERVER_DIR" \
  "$SERVER_DIR/PalServer.sh -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS"

serverlib::write_update_script "/usr/local/bin/palworld-update" \
  "palworld" "$SVC_USER" "$STEAMCMD_DIR" "$SERVER_DIR" "$APPID"
serverlib::write_backup_script "/usr/local/bin/palworld-backup" \
  "$SVC_USER" "$SERVER_DIR/Pal/Saved" "SaveGames" "$BACKUP_DIR"

serverlib::allow_ports "$GAME_PORT/udp"

serverlib::log "Starting the server…"
systemctl start palworld

# ── Summary ──────────────────────────────────────────────────────────────────
ip_addr="$(serverlib::detect_ip)"
gen_note=""
if [[ "$ADMIN_GENERATED" == "true" ]]; then
  gen_note="  (auto-generated — save it now)"
fi

cat <<EOF

──────────────────────────────────────────────────────────────
 Palworld 1.0 server installed and starting.
──────────────────────────────────────────────────────────────
 Connect (in-game -> Join Multiplayer -> enter IP):
     ${ip_addr:-<server-ip>}:$GAME_PORT
 Admin password:
     $ADMIN_PASSWORD$gen_note

 Config : $ini
 Saves  : $SERVER_DIR/Pal/Saved/SaveGames

 Commands:
     journalctl -u palworld -f     # live logs
     systemctl stop palworld       # stop BEFORE editing the config
     systemctl restart palworld    # restart
     palworld-update               # update after a patch
     palworld-backup               # snapshot the save

 The server rewrites parts of the config on shutdown — always stop it
 before editing PalWorldSettings.ini. For a daily restart, add cron:
     0 5 * * * root systemctl restart palworld
──────────────────────────────────────────────────────────────
EOF
