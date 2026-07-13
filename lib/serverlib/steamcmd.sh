#!/usr/bin/env bash
# SteamCMD install + app management, and the steamclient.so fix.
# Depends on: log, util (run_as).
if [[ -n "${_SERVERLIB_STEAMCMD:-}" ]]; then return 0; fi
_SERVERLIB_STEAMCMD=1
# shellcheck source=log.sh
source "${BASH_SOURCE[0]%/*}/log.sh"
# shellcheck source=util.sh
source "${BASH_SOURCE[0]%/*}/util.sh"

# Where Valve publishes the SteamCMD bootstrap tarball.
readonly SERVERLIB_STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"

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
  local attempt max=5
  serverlib::log "Installing/updating Steam app $appid (first run is a large download)…"
  # SteamCMD frequently fails the first attempt with a transient "Missing
  # configuration" / appmanifest error; retrying a few times is the standard fix.
  for (( attempt=1; attempt<=max; attempt++ )); do
    if serverlib::run_as "$user" "$steamcmd_dir/steamcmd.sh" \
        +force_install_dir "$install_dir" \
        +login anonymous \
        +app_update "$appid" validate \
        +quit; then
      return 0
    fi
    serverlib::warn "SteamCMD attempt $attempt/$max failed (common on first run); retrying in 5s…"
    sleep 5
  done
  serverlib::die "SteamCMD could not install app $appid after $max attempts — run the steamcmd command manually to see the underlying error."
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
