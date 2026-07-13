#!/usr/bin/env bash
# systemd unit rendering + installation. Depends on: log.
if [[ -n "${_SERVERLIB_SYSTEMD:-}" ]]; then return 0; fi
_SERVERLIB_SYSTEMD=1
# shellcheck source=log.sh
source "${BASH_SOURCE[0]%/*}/log.sh"

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
