#!/usr/bin/env bash
#
# ARK: Survival Evolved dedicated server installer for Debian (12/13). Run as root.
#   sudo ./ark-se.sh
#
# This is ARK: Survival Evolved (ASE, app 376030) — NOT Survival Ascended (ASA),
# whose dedicated server is Windows-only. ASE has a native Linux server.
#
# ARK reads its core settings from the launch command line, so there is no INI to
# pre-edit. GameUserSettings.ini / Game.ini are generated on first boot for
# fine-tuning later. Re-running is safe.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=lib/serverlib.sh
source "$SCRIPT_DIR/lib/serverlib.sh"

# ─────────────────────────────────────────────────────────────────────────────
#  EDIT THESE
# ─────────────────────────────────────────────────────────────────────────────
SESSION_NAME="My ARK Server"    # name shown in the server browser
SERVER_PASSWORD=""               # empty = open server (avoid ? and spaces)
ADMIN_PASSWORD=""                # empty = auto-generate (avoid ? and spaces)
MAX_PLAYERS=70                   # ARK default cap; size to your RAM
MAP="TheIsland"                  # TheIsland, ScorchedEarth_P, Ragnarok, Aberration_P, etc.

GAME_PORT=7777                   # UDP game port
QUERY_PORT=27015                 # UDP Steam query port (server browser)

SVC_USER="arkse"
BASE_DIR="/opt/ark-se"
# ─────────────────────────────────────────────────────────────────────────────

SERVERLIB_TAG="ark-se"
readonly APPID=376030
STEAMCMD_DIR="$BASE_DIR/steamcmd"
SERVER_DIR="$BASE_DIR/server"
BINARY_DIR="$SERVER_DIR/ShooterGame/Binaries/Linux"
CONFIG_DIR="$SERVER_DIR/ShooterGame/Saved/Config/LinuxServer"
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

 Config (after first boot, for fine-tuning):
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
