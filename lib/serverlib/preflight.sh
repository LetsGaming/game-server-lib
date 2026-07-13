#!/usr/bin/env bash
# Preflight checks. Depends on: log.
if [[ -n "${_SERVERLIB_PREFLIGHT:-}" ]]; then return 0; fi
_SERVERLIB_PREFLIGHT=1
# shellcheck source=log.sh
source "${BASH_SOURCE[0]%/*}/log.sh"

serverlib::require_root() {
  [[ $EUID -eq 0 ]] || serverlib::die "Run as root (use sudo)."
}

serverlib::require_systemd() {
  command -v systemctl >/dev/null 2>&1 || serverlib::die "systemd is required."
}
