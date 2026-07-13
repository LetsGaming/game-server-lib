#!/usr/bin/env bash
#
# serverlib.sh — shared helpers for SteamCMD-based dedicated game server
# installers on Debian.
#
# Source this from a game script. It defines functions under the `serverlib::`
# namespace and has NO side effects on load. The sourcing script is expected to
# run under `set -euo pipefail`.
#
# Per-game scripts own their config (paths, ports, launch command); this library
# owns everything the games share: deps, service user, SteamCMD, the
# steamclient.so fix, systemd unit generation, firewall, and update/backup
# helper generation.

# Where Valve publishes the SteamCMD bootstrap tarball.
readonly SERVERLIB_STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"

# ─────────────────────────────────────────────────────────────────────────────
#  Logging  (games set SERVERLIB_TAG to get a per-game prefix)
# ─────────────────────────────────────────────────────────────────────────────
serverlib::log()  { printf '\033[1;36m[%s]\033[0m %s\n' "${SERVERLIB_TAG:-server}" "$*"; }
serverlib::warn() { printf '\033[1;33m[%s]\033[0m %s\n' "${SERVERLIB_TAG:-server}" "$*" >&2; }
serverlib::die()  { printf '\033[1;31m[%s]\033[0m %s\n' "${SERVERLIB_TAG:-server}" "$*" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
#  Preflight
# ─────────────────────────────────────────────────────────────────────────────
serverlib::require_root() {
  [[ $EUID -eq 0 ]] || serverlib::die "Run as root (use sudo)."
}

serverlib::require_systemd() {
  command -v systemctl >/dev/null 2>&1 || serverlib::die "systemd is required."
}

# ─────────────────────────────────────────────────────────────────────────────
#  Pure utilities (no side effects — safe to unit test)
# ─────────────────────────────────────────────────────────────────────────────

# Escape a string for the replacement side of `sed s|...|...|`.
serverlib::sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# Print a random alphanumeric password. usage: serverlib::gen_password [LEN]
serverlib::gen_password() {
  local len="${1:-20}" pw
  pw="$(openssl rand -base64 $((len * 2)) 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-"$len")"
  if [[ -z "$pw" ]]; then
    pw="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len")"
  fi
  printf '%s' "$pw"
}

# Best-effort primary IPv4 of this host.
serverlib::detect_ip() { hostname -I 2>/dev/null | awk '{print $1}'; }

# Render a systemd unit to stdout (pure — no writes).
# usage: serverlib::render_systemd_unit DESC USER WORKDIR EXEC_START [EXEC_STOP]
serverlib::render_systemd_unit() {
  local desc="$1" user="$2" workdir="$3" exec_start="$4" exec_stop="${5:-}"
  printf '[Unit]\n'
  printf 'Description=%s\n' "$desc"
  printf 'After=network-online.target\n'
  printf 'Wants=network-online.target\n\n'
  printf '[Service]\n'
  printf 'Type=simple\n'
  printf 'User=%s\n' "$user"
  printf 'Group=%s\n' "$user"
  printf 'WorkingDirectory=%s\n' "$workdir"
  printf 'ExecStart=%s\n' "$exec_start"
  if [[ -n "$exec_stop" ]]; then
    printf 'ExecStop=%s\n' "$exec_stop"
  fi
  printf 'Restart=on-failure\n'
  printf 'RestartSec=15\n'
  # ARK in particular opens a very large number of files; 100000 is the
  # community-standard floor and harmless for lighter servers.
  printf 'LimitNOFILE=100000\n\n'
  printf '[Install]\n'
  printf 'WantedBy=multi-user.target\n'
}

# ─────────────────────────────────────────────────────────────────────────────
#  Run a command as the service user (with its HOME from /etc/passwd)
# ─────────────────────────────────────────────────────────────────────────────
# usage: serverlib::run_as USER CMD [ARGS...]
serverlib::run_as() {
  local user="$1"; shift
  sudo -u "$user" -H "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Provisioning (these touch the system — root required)
# ─────────────────────────────────────────────────────────────────────────────

# Install SteamCMD prerequisites. Extra distro packages may be passed as args.
# usage: serverlib::install_base_deps [EXTRA_PKG...]
serverlib::install_base_deps() {
  serverlib::log "Installing base dependencies (enabling i386 for SteamCMD)…"
  dpkg --add-architecture i386
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl tar lib32gcc-s1 "$@"
}

# Create an unprivileged, non-login service account if it doesn't exist.
# usage: serverlib::create_service_user USER HOME_DIR
serverlib::create_service_user() {
  local user="$1" home="$2"
  if id -u "$user" >/dev/null 2>&1; then
    return 0
  fi
  serverlib::log "Creating service user '$user'…"
  useradd --create-home --home-dir "$home" --shell /usr/sbin/nologin "$user"
}

# Download + unpack SteamCMD into a directory owned by the service user (idempotent).
# usage: serverlib::install_steamcmd USER STEAMCMD_DIR
serverlib::install_steamcmd() {
  local user="$1" dir="$2"
  if [[ -x "$dir/steamcmd.sh" ]]; then
    return 0
  fi
  serverlib::log "Downloading SteamCMD…"
  serverlib::run_as "$user" curl -fsSL "$SERVERLIB_STEAMCMD_URL" -o "$dir/steamcmd.tar.gz"
  serverlib::run_as "$user" tar -xzf "$dir/steamcmd.tar.gz" -C "$dir"
  serverlib::run_as "$user" rm -f "$dir/steamcmd.tar.gz"
}

# Install or update a Steam app anonymously.
# usage: serverlib::steam_app_update USER STEAMCMD_DIR INSTALL_DIR APPID
serverlib::steam_app_update() {
  local user="$1" steamcmd_dir="$2" install_dir="$3" appid="$4"
  serverlib::log "Installing/updating Steam app $appid (first run is a large download)…"
  serverlib::run_as "$user" "$steamcmd_dir/steamcmd.sh" \
    +force_install_dir "$install_dir" \
    +login anonymous \
    +app_update "$appid" validate \
    +quit
}

# Create the steamclient.so symlinks the servers look for under ~/.steam.
# Without these, both Palworld and ARK fail on first launch with an SDK error.
# usage: serverlib::link_steamclient USER HOME_DIR STEAMCMD_DIR
serverlib::link_steamclient() {
  local user="$1" home="$2" steamcmd_dir="$3"
  serverlib::log "Linking steamclient.so…"
  serverlib::run_as "$user" mkdir -p "$home/.steam/sdk32" "$home/.steam/sdk64"
  serverlib::run_as "$user" ln -sf "$steamcmd_dir/linux32/steamclient.so" "$home/.steam/sdk32/steamclient.so"
  serverlib::run_as "$user" ln -sf "$steamcmd_dir/linux64/steamclient.so" "$home/.steam/sdk64/steamclient.so"
}

# Write and enable a systemd unit (does not start it).
# usage: serverlib::install_systemd_service NAME DESC USER WORKDIR EXEC_START [EXEC_STOP]
serverlib::install_systemd_service() {
  local name="$1" desc="$2" user="$3" workdir="$4" exec_start="$5" exec_stop="${6:-}"
  serverlib::log "Installing systemd service '$name'…"
  serverlib::render_systemd_unit "$desc" "$user" "$workdir" "$exec_start" "$exec_stop" \
    > "/etc/systemd/system/${name}.service"
  systemctl daemon-reload
  systemctl enable "$name" >/dev/null
}

# Open ports in ufw if it's active; otherwise warn to open them upstream.
# usage: serverlib::allow_ports "7777/udp" "27015/udp" ...
serverlib::allow_ports() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    local spec
    for spec in "$@"; do
      serverlib::log "Opening $spec in ufw…"
      ufw allow "$spec" >/dev/null || true
    done
  else
    serverlib::warn "ufw not active — ensure these are open at your VM/Proxmox firewall: $*"
  fi
}

# Generate an update helper at PATH: stop → SteamCMD update → start.
# usage: serverlib::write_update_script PATH SERVICE USER STEAMCMD_DIR INSTALL_DIR APPID
serverlib::write_update_script() {
  local path="$1" service="$2" user="$3" steamcmd_dir="$4" install_dir="$5" appid="$6"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Stop -> pull latest server build -> start. Run after each game patch.\n'
    printf 'set -euo pipefail\n'
    printf '[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }\n'
    printf 'systemctl stop %s\n' "$service"
    printf 'sudo -u %s -H %s/steamcmd.sh +force_install_dir %s +login anonymous +app_update %s validate +quit\n' \
      "$user" "$steamcmd_dir" "$install_dir" "$appid"
    printf 'systemctl start %s\n' "$service"
    printf 'echo "Updated and restarted."\n'
  } > "$path"
  chmod +x "$path"
}

# Generate a backup helper at PATH: tar SAVE_PARENT/SAVE_DIR into BACKUP_DIR,
# keeping the KEEP most recent archives (default 14).
# usage: serverlib::write_backup_script PATH USER SAVE_PARENT SAVE_DIR BACKUP_DIR [KEEP]
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
