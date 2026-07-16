#!/usr/bin/env bash
#
# Reset the Palworld server. Run as root.
#
#   sudo ./reset.sh                    # re-apply settings, KEEP the world
#   sudo ./reset.sh --wipe-world       # also delete the save = brand-new world
#   sudo ./reset.sh --wipe-world --yes # ...without the confirmation prompt
#
# Why this exists: editing options.conf or .env does nothing on a running
# server. install.sh won't touch an existing PalWorldSettings.ini, and Palworld
# writes a WorldOption.sav into the save on world creation which from then on
# silently overrides the .ini. This script clears both and regenerates.
#
# Always takes a backup first. Fast — it does not re-run SteamCMD.

set -euo pipefail

# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/common.sh"

WIPE_WORLD=false
ASSUME_YES=false

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --wipe-world) WIPE_WORLD=true ;;
    --yes|-y)     ASSUME_YES=true ;;
    --help|-h)    usage; exit 0 ;;
    *)            serverlib::die "Unknown option: $arg (try --help)" ;;
  esac
done

serverlib::require_root
serverlib::require_systemd

# Read the current admin password out of the config before we delete it.
palworld::resolve_admin_password

if [[ "$WIPE_WORLD" == "true" && "$ASSUME_YES" != "true" ]]; then
  serverlib::warn "This DELETES the world at $SAVE_ROOT. A backup is taken first, but this is not undoable in place."
  read -r -p "Type YES to wipe the world: " reply
  [[ "$reply" == "YES" ]] || serverlib::die "Aborted — nothing changed."
fi

# ── Stop ─────────────────────────────────────────────────────────────────────
if systemctl is-active --quiet palworld; then
  serverlib::log "Stopping the server…"
  systemctl stop palworld
fi

palworld::backup_now

# ── Clear ────────────────────────────────────────────────────────────────────
if [[ -f "$CONFIG_INI" ]]; then
  serverlib::log "Removing the generated PalWorldSettings.ini…"
  rm -f "$CONFIG_INI"
fi

if [[ "$WIPE_WORLD" == "true" ]]; then
  if [[ -d "$SAVE_ROOT" ]]; then
    serverlib::log "Deleting save data…"
    rm -rf "${SAVE_ROOT:?}"
  fi
else
  # WorldOption.sav overrides the .ini on an existing world; drop it so the
  # regenerated settings are actually read. World-generation settings baked in
  # at creation (e.g. the seed) still won't change without --wipe-world.
  if [[ -d "$SAVE_ROOT" ]]; then
    while IFS= read -r -d '' opt; do
      serverlib::log "Removing $opt (it overrides the .ini)…"
      rm -f "$opt"
    done < <(find "$SAVE_ROOT" -name 'WorldOption.sav' -print0 2>/dev/null)
  fi
fi

# ── Regenerate ───────────────────────────────────────────────────────────────
palworld::render_config
palworld::sync_mods
chown -R "$SVC_USER:$SVC_USER" "$SAVED_DIR" 2>/dev/null || true

# ── Start ────────────────────────────────────────────────────────────────────
serverlib::log "Starting the server…"
systemctl start palworld

ip_addr="$(serverlib::detect_ip)"
mode="settings re-applied, world kept"
if [[ "$WIPE_WORLD" == "true" ]]; then
  mode="settings re-applied, WORLD WIPED (fresh start)"
fi

cat <<EOF

──────────────────────────────────────────────────────────────
 Palworld server reset: $mode
──────────────────────────────────────────────────────────────
 Connect      : ${ip_addr:-<server-ip>}:$GAME_PORT
 Admin pass   : $ADMIN_PASSWORD$ADMIN_PASSWORD_NOTE
 Backups      : $BACKUP_DIR

 Watch it come up:  journalctl -u palworld -f
──────────────────────────────────────────────────────────────
EOF
