#!/usr/bin/env bash
# Generators for the per-game update/backup helper scripts. No dependencies.
if [[ -n "${_SERVERLIB_HELPERS:-}" ]]; then return 0; fi
_SERVERLIB_HELPERS=1

# Generate an update helper at PATH: stop → SteamCMD update (with retries) → start.
# usage: serverlib::write_update_script PATH SERVICE USER STEAMCMD_DIR INSTALL_DIR APPID
# The printf templates single-quote $EUID/$i on purpose: they must stay literal in
# the generated script (expanded when that runs, not while generating it).
# shellcheck disable=SC2016
serverlib::write_update_script() {
  local path="$1" service="$2" user="$3" steamcmd_dir="$4" install_dir="$5" appid="$6"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Stop -> pull latest server build -> start. Run after each game patch.\n'
    printf 'set -euo pipefail\n'
    printf '[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }\n'
    printf 'systemctl stop %s\n' "$service"
    printf 'for i in 1 2 3; do\n'
    printf '  sudo -u %s -H %s/steamcmd.sh +force_install_dir %s +login anonymous +app_update %s validate +quit && break\n' \
      "$user" "$steamcmd_dir" "$install_dir" "$appid"
    printf '  echo "SteamCMD attempt $i failed; retrying in 5s…"; sleep 5\n'
    printf 'done\n'
    printf 'systemctl start %s\n' "$service"
    printf 'echo "Updated and restarted."\n'
  } > "$path"
  chmod +x "$path"
}

# Generate a backup helper at PATH: tar SAVE_PARENT/SAVE_DIR into BACKUP_DIR,
# keeping the KEEP most recent archives (default 14).
# usage: serverlib::write_backup_script PATH USER SAVE_PARENT SAVE_DIR BACKUP_DIR [KEEP]
# The printf templates single-quote $stamp/$src/$dst on purpose: they must stay
# literal in the generated script (expanded when that runs, not while generating).
# shellcheck disable=SC2016
serverlib::write_backup_script() {
  local path="$1" user="$2" save_parent="$3" save_dir="$4" backup_dir="$5" keep="${6:-14}"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Snapshot the save directory. Game saves can corrupt; back up often.\n'
    printf 'set -euo pipefail\n'
    printf 'stamp="$(date +%%Y%%m%%d-%%H%%M%%S)"\n'
    printf 'src="%s/%s"\n' "$save_parent" "$save_dir"
    printf 'dst="%s/backup-$stamp.tar.gz"\n' "$backup_dir"
    printf '[[ -d "$src" ]] || { echo "No save directory yet at $src"; exit 1; }\n'
    printf 'tar -czf "$dst" -C "%s" "%s"\n' "$save_parent" "$save_dir"
    printf 'chown %s:%s "$dst"\n' "$user" "$user"
    printf 'ls -1t "%s"/backup-*.tar.gz 2>/dev/null | tail -n +%d | xargs -r rm -f\n' \
      "$backup_dir" "$((keep + 1))"
    printf 'echo "Backup written: $dst"\n'
  } > "$path"
  chmod +x "$path"
}
