#!/usr/bin/env bash
#
# Palworld 1.0 dedicated server installer for Debian/Ubuntu. Run as root.
#
#   cp .env.example .env      # then edit .env (optional — defaults work)
#   sudo ./install.sh
#
# All configuration comes from .env and options.conf — you never edit this
# script. Re-running is safe; an existing PalWorldSettings.ini is preserved
# (use ./reset.sh to re-apply changed settings).

set -euo pipefail

# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/common.sh"

serverlib::require_root
serverlib::require_systemd
palworld::resolve_admin_password

# ── Install ──────────────────────────────────────────────────────────────────
serverlib::install_base_deps
serverlib::create_service_user "$SVC_USER" "$BASE_DIR"
mkdir -p "$STEAMCMD_DIR" "$SERVER_DIR" "$BACKUP_DIR"
chown -R "$SVC_USER:$SVC_USER" "$BASE_DIR"

serverlib::install_steamcmd "$SVC_USER" "$STEAMCMD_DIR"
serverlib::steam_app_update "$SVC_USER" "$STEAMCMD_DIR" "$SERVER_DIR" "$PALWORLD_APPID"
serverlib::link_steamclient "$SVC_USER" "$BASE_DIR" "$STEAMCMD_DIR"

# ── Config ───────────────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
chown -R "$SVC_USER:$SVC_USER" "$SAVED_DIR" 2>/dev/null || true

if [[ -f "$CONFIG_INI" ]]; then
  serverlib::warn "PalWorldSettings.ini exists — leaving it as-is (use ./reset.sh to re-apply settings)."
else
  palworld::render_config
fi

palworld::sync_mods

# ── Service, helpers, firewall ───────────────────────────────────────────────
serverlib::install_systemd_service \
  "palworld" "Palworld Dedicated Server" "$SVC_USER" "$SERVER_DIR" \
  "$SERVER_DIR/PalServer.sh -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS"

serverlib::write_update_script "/usr/local/bin/palworld-update" \
  "palworld" "$SVC_USER" "$STEAMCMD_DIR" "$SERVER_DIR" "$PALWORLD_APPID"
serverlib::write_backup_script "/usr/local/bin/palworld-backup" \
  "$SVC_USER" "$SAVED_DIR" "SaveGames" "$BACKUP_DIR"

serverlib::allow_ports "$GAME_PORT/udp"

serverlib::log "Starting the server…"
systemctl start palworld

# ── Summary ──────────────────────────────────────────────────────────────────
ip_addr="$(serverlib::detect_ip)"

cat <<EOF

──────────────────────────────────────────────────────────────
 Palworld 1.0 server installed and starting.
──────────────────────────────────────────────────────────────
 Connect (in-game -> Join Multiplayer -> enter IP):
     ${ip_addr:-<server-ip>}:$GAME_PORT
 Admin password:
     $ADMIN_PASSWORD$ADMIN_PASSWORD_NOTE

 Settings : options.conf + .env  ->  $CONFIG_INI
 Saves    : $SAVE_ROOT

 Commands:
     journalctl -u palworld -f     # live logs
     ./reset.sh                    # re-apply changed settings (keeps world)
     ./reset.sh --wipe-world       # fresh world
     palworld-update               # update after a patch
     palworld-backup               # snapshot the save

 For a daily restart (Palworld leaks memory), add cron:
     0 5 * * * root systemctl restart palworld
──────────────────────────────────────────────────────────────
EOF
