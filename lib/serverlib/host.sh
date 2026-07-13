#!/usr/bin/env bash
# Host provisioning: packages, service account, firewall. Depends on: log.
if [[ -n "${_SERVERLIB_HOST:-}" ]]; then return 0; fi
_SERVERLIB_HOST=1
# shellcheck source=log.sh
source "${BASH_SOURCE[0]%/*}/log.sh"

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
