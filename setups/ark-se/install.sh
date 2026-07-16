#!/usr/bin/env bash
#
# ARK: Survival Evolved dedicated server installer for Debian (12/13). Run as root.
#
#   cp .env.example .env      # then edit .env (optional — defaults work)
#   sudo ./install.sh
#
# This is ARK: Survival Evolved (ASE, app 376030) — NOT Survival Ascended (ASA),
# whose dedicated server is Windows-only. ASE has a native Linux server.
#
# All configuration comes from .env / .env.example — you never edit this script.
# Server identity comes from the launch command; gameplay/difficulty settings are
# generated into GameUserSettings.ini / Game.ini from the editable .conf sources.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." &>/dev/null && pwd)"
# shellcheck source=../../lib/serverlib.sh
source "$REPO_ROOT/lib/serverlib.sh"

serverlib::set_tag "ark-se"

# Config: defaults from .env.example, overridden by your .env. Both are parsed
# literally (not sourced), so values with $, !, quotes or backticks are safe.
serverlib::load_env "$SCRIPT_DIR/.env.example"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  serverlib::load_env "$SCRIPT_DIR/.env"
else
  serverlib::warn "No .env found — using .env.example defaults. Copy it to .env to customize."
fi

readonly APPID=376030
STEAMCMD_DIR="$BASE_DIR/steamcmd"
SERVER_DIR="$BASE_DIR/server"
BINARY_DIR="$SERVER_DIR/ShooterGame/Binaries/Linux"
CONFIG_DIR="$SERVER_DIR/ShooterGame/Saved/Config/LinuxServer"
GUS_SOURCE="$SCRIPT_DIR/gameusersettings.conf"
GAME_SOURCE="$SCRIPT_DIR/game.conf"
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

# ── Config (ARK-specific) ────────────────────────────────────────────────────
# Generate GameUserSettings.ini + Game.ini from the editable .conf sources
# (comments stripped). ARK reads these on boot; existing files are preserved.
mkdir -p "$CONFIG_DIR"
chown -R "$SVC_USER:$SVC_USER" "$SERVER_DIR/ShooterGame/Saved" 2>/dev/null || true

write_ini() {  # DEST_NAME  SOURCE
  local dest="$CONFIG_DIR/$1" src="$2"
  if [[ -f "$dest" ]]; then
    serverlib::warn "$1 exists — leaving it as-is."
    return 0
  fi
  [[ -f "$src" ]] || serverlib::die "Config source missing: $src"
  serverlib::log "Writing $1 from $(basename "$src")…"
  serverlib::strip_comments "$src" > "$dest"
  chown "$SVC_USER:$SVC_USER" "$dest"
}
write_ini GameUserSettings.ini "$GUS_SOURCE"
write_ini Game.ini             "$GAME_SOURCE"

# ── Launch command (ARK-specific) ────────────────────────────────────────────
# ARK options live in a '?'-delimited query string as argv[1]; flags follow it.
# The query portion is wrapped in quotes so systemd keeps it as ONE argument
# even when the session name contains spaces.
query="${MAP}?listen"
query+="?SessionName=${SESSION_NAME}"
query+="?Port=${GAME_PORT}"
query+="?QueryPort=${QUERY_PORT}"
query+="?MaxPlayers=${MAX_PLAYERS}"
query+="?ServerAdminPassword=${ADMIN_PASSWORD}"
if [[ -n "$SERVER_PASSWORD" ]]; then
  query+="?ServerPassword=${SERVER_PASSWORD}"
fi

exec_start="$BINARY_DIR/ShooterGameServer \"$query\" -server -log"
# $MAINPID is a systemd specifier — it must stay literal, not expand here.
# shellcheck disable=SC2016
exec_stop='/bin/kill -s INT $MAINPID'   # ARK saves the world on SIGINT

# ── Service, helpers, firewall ───────────────────────────────────────────────
serverlib::install_systemd_service \
  "ark-se" "ARK: Survival Evolved Dedicated Server" "$SVC_USER" "$BINARY_DIR" \
  "$exec_start" "$exec_stop"

serverlib::write_update_script "/usr/local/bin/ark-se-update" \
  "ark-se" "$SVC_USER" "$STEAMCMD_DIR" "$SERVER_DIR" "$APPID"
serverlib::write_backup_script "/usr/local/bin/ark-se-backup" \
  "$SVC_USER" "$SERVER_DIR/ShooterGame" "Saved" "$BACKUP_DIR"

serverlib::allow_ports "$GAME_PORT/udp" "$((GAME_PORT + 1))/udp" "$QUERY_PORT/udp"

serverlib::log "Starting the server (first boot generates the world and can take a few minutes)…"
systemctl start ark-se

# ── Summary ──────────────────────────────────────────────────────────────────
ip_addr="$(serverlib::detect_ip)"
gen_note=""
if [[ "$ADMIN_GENERATED" == "true" ]]; then
  gen_note="  (auto-generated — save it now)"
fi

cat <<EOF

──────────────────────────────────────────────────────────────
 ARK: Survival Evolved server installed and starting.
──────────────────────────────────────────────────────────────
 Map          : $MAP
 Join         : Steam client -> View -> Servers -> Favorites,
                add  ${ip_addr:-<server-ip>}:$QUERY_PORT  and connect.
                Or in-game console:  open ${ip_addr:-<server-ip>}:$GAME_PORT
 Admin pass   : $ADMIN_PASSWORD$gen_note

 Settings   : edit gameusersettings.conf and game.conf (this folder), then
              re-run install.sh. Difficulty is a tuned medium — see README.md.
              Generated into:
                $CONFIG_DIR/GameUserSettings.ini
                $CONFIG_DIR/Game.ini
 Saves : $SERVER_DIR/ShooterGame/Saved

 Ports opened : $GAME_PORT/udp, $((GAME_PORT + 1))/udp, $QUERY_PORT/udp
 (RCON 27020/tcp is left CLOSED — only open it if you enable RCON.)

 Commands:
     journalctl -u ark-se -f     # live logs
     systemctl stop ark-se       # stop BEFORE editing the config
     systemctl restart ark-se    # restart
     ark-se-update               # update after a patch
     ark-se-backup               # snapshot the save
──────────────────────────────────────────────────────────────
EOF
