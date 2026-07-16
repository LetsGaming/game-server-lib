#!/usr/bin/env bash
#
# Shared by install.sh and reset.sh: loads config, derives paths, and renders
# the Palworld-specific config. Sourced, never run directly.
#
# The paths and flags below are consumed by the scripts that source this file,
# which ShellCheck can't see when it lints this file on its own — hence:
# shellcheck disable=SC2034

if [[ -n "${_PALWORLD_COMMON:-}" ]]; then return 0; fi
_PALWORLD_COMMON=1

PALWORLD_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$PALWORLD_DIR/../.." &>/dev/null && pwd)"
# shellcheck source=../../lib/serverlib.sh
source "$REPO_ROOT/lib/serverlib.sh"

serverlib::set_tag "palworld"

readonly PALWORLD_APPID=2394010

# Config: defaults from .env.example, overridden by your .env. Both are parsed
# literally (not sourced), so values with $, !, quotes or backticks are safe.
serverlib::load_env "$PALWORLD_DIR/.env.example"
if [[ -f "$PALWORLD_DIR/.env" ]]; then
  serverlib::load_env "$PALWORLD_DIR/.env"
else
  serverlib::warn "No .env found — using .env.example defaults. Copy it to .env to customize."
fi

# Paths derived from BASE_DIR
STEAMCMD_DIR="$BASE_DIR/steamcmd"
SERVER_DIR="$BASE_DIR/server"
SAVED_DIR="$SERVER_DIR/Pal/Saved"
CONFIG_DIR="$SAVED_DIR/Config/LinuxServer"
CONFIG_INI="$CONFIG_DIR/PalWorldSettings.ini"
SAVE_ROOT="$SAVED_DIR/SaveGames"
BACKUP_DIR="$BASE_DIR/backups"
CONFIG_SOURCE="$PALWORLD_DIR/options.conf"
MODS_SOURCE="$PALWORLD_DIR/mods"
MODS_DEST="$SERVER_DIR/Pal/Content/Paks/~mods"
BACKUP_HELPER="/usr/local/bin/palworld-backup"

# Decide which admin password to use, in priority order:
#   1. ADMIN_PASSWORD from .env
#   2. the one already in the generated config (so a reset doesn't silently
#      change it out from under you)
#   3. a freshly generated one
# Sets ADMIN_PASSWORD and ADMIN_PASSWORD_NOTE. Call BEFORE deleting the config.
palworld::resolve_admin_password() {
  if [[ -n "$ADMIN_PASSWORD" ]]; then
    ADMIN_PASSWORD_NOTE=""
    return 0
  fi
  local existing=""
  if [[ -f "$CONFIG_INI" ]]; then
    existing="$(sed -n 's/.*AdminPassword="\([^"]*\)".*/\1/p' "$CONFIG_INI" | head -1)"
  fi
  if [[ -n "$existing" ]]; then
    ADMIN_PASSWORD="$existing"
    ADMIN_PASSWORD_NOTE="  (kept from the existing config)"
  else
    ADMIN_PASSWORD="$(serverlib::gen_password)"
    ADMIN_PASSWORD_NOTE="  (auto-generated — save it now)"
  fi
}

# Compile options.conf into the single-line OptionSettings=(...) Palworld needs,
# then patch in the .env values. Overwrites any existing config.
palworld::render_config() {
  [[ -f "$CONFIG_SOURCE" ]] || serverlib::die "Config source missing: $CONFIG_SOURCE"
  serverlib::log "Writing PalWorldSettings.ini from options.conf…"
  mkdir -p "$CONFIG_DIR"
  {
    printf '[/Script/Pal.PalGameWorldSettings]\n'
    printf 'OptionSettings=(%s)\n' "$(serverlib::flatten_conf "$CONFIG_SOURCE")"
  } > "$CONFIG_INI"
  sed -i "s|ServerName=\"[^\"]*\"|ServerName=\"$(serverlib::sed_escape "$SERVER_NAME")\"|"                       "$CONFIG_INI"
  sed -i "s|ServerDescription=\"[^\"]*\"|ServerDescription=\"$(serverlib::sed_escape "$SERVER_DESCRIPTION")\"|"   "$CONFIG_INI"
  sed -i "s|AdminPassword=\"[^\"]*\"|AdminPassword=\"$(serverlib::sed_escape "$ADMIN_PASSWORD")\"|"               "$CONFIG_INI"
  sed -i "s|ServerPassword=\"[^\"]*\"|ServerPassword=\"$(serverlib::sed_escape "$SERVER_PASSWORD")\"|"            "$CONFIG_INI"
  sed -i "s|ServerPlayerMaxNum=[0-9]*|ServerPlayerMaxNum=$MAX_PLAYERS|"                                           "$CONFIG_INI"
  sed -i "s|PublicPort=[0-9]*|PublicPort=$GAME_PORT|"                                                             "$CONFIG_INI"
  if [[ "$DISABLE_INVADERS" == "true" ]]; then
    sed -i "s|bEnableInvaderEnemy=[A-Za-z]*|bEnableInvaderEnemy=False|"                                           "$CONFIG_INI"
  fi
  chown "$SVC_USER:$SVC_USER" "$CONFIG_INI"
}

# Mirror mods/*.pak into the server's Pal/Content/Paks/~mods.
# The mods/ folder is the source of truth: removing a .pak from it and re-running
# removes it from the server too (Pocketpair require deleting old mods before a
# game update — disabling is not enough).
# NOTE: Palworld's official mod loader is Windows-only, so this only covers plain
# .pak content mods. See mods/README.md.
palworld::sync_mods() {
  local paks=()
  if [[ -d "$MODS_SOURCE" ]]; then
    shopt -s nullglob
    paks=("$MODS_SOURCE"/*.pak)
    shopt -u nullglob
  fi

  if [[ -d "$MODS_DEST" ]]; then
    rm -rf "${MODS_DEST:?}"
  fi

  if [[ ${#paks[@]} -eq 0 ]]; then
    return 0
  fi

  serverlib::log "Installing ${#paks[@]} .pak mod(s) into ~mods…"
  mkdir -p "$MODS_DEST"
  cp -- "${paks[@]}" "$MODS_DEST/"
  chown -R "$SVC_USER:$SVC_USER" "$MODS_DEST"
  serverlib::warn "Mods are unsupported on the Linux server — if it misbehaves, empty mods/ and re-run."
}

# Snapshot the save via the installed helper, if there is one.
palworld::backup_now() {
  if [[ -x "$BACKUP_HELPER" ]]; then
    serverlib::log "Backing up the save first…"
    "$BACKUP_HELPER" || serverlib::warn "Backup skipped (no save data yet?) — continuing."
  else
    serverlib::warn "$BACKUP_HELPER not found — no backup taken. Run install.sh first."
  fi
}
