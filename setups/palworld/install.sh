#!/usr/bin/env bash
#
# Palworld 1.0 dedicated server installer for Debian (12/13). Run as root.
#
#   cp .env.example .env      # then edit .env (optional — defaults work)
#   sudo ./install.sh
#
# All configuration comes from .env / .env.example — you never edit this script.
# Re-running is safe; an existing PalWorldSettings.ini is preserved.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." &>/dev/null && pwd)"
# shellcheck source=../../lib/serverlib.sh
source "$REPO_ROOT/lib/serverlib.sh"

serverlib::set_tag "palworld"

# Config: defaults from .env.example, overridden by your .env. Both are parsed
# literally (not sourced), so values with $, !, quotes or backticks are safe.
serverlib::load_env "$SCRIPT_DIR/.env.example"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  serverlib::load_env "$SCRIPT_DIR/.env"
else
  serverlib::warn "No .env found — using .env.example defaults. Copy it to .env to customize."
fi

readonly APPID=2394010
STEAMCMD_DIR="$BASE_DIR/steamcmd"
SERVER_DIR="$BASE_DIR/server"
CONFIG_DIR="$SERVER_DIR/Pal/Saved/Config/LinuxServer"
CONFIG_SOURCE="$SCRIPT_DIR/options.conf"
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
# Compile options.conf (human-editable, one setting per line) into the single
# OptionSettings=(...) line Palworld requires, then patch in the .env values.
# Existing configs are preserved.
mkdir -p "$CONFIG_DIR"
chown -R "$SVC_USER:$SVC_USER" "$SERVER_DIR/Pal/Saved" 2>/dev/null || true

ini="$CONFIG_DIR/PalWorldSettings.ini"
if [[ -f "$ini" ]]; then
  serverlib::warn "PalWorldSettings.ini exists — leaving it as-is."
else
  [[ -f "$CONFIG_SOURCE" ]] || serverlib::die "Config source missing: $CONFIG_SOURCE"
  serverlib::log "Writing PalWorldSettings.ini from options.conf…"
  {
    printf '[/Script/Pal.PalGameWorldSettings]\n'
    printf 'OptionSettings=(%s)\n' "$(serverlib::flatten_conf "$CONFIG_SOURCE")"
  } > "$ini"
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
