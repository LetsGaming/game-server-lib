#!/usr/bin/env bash
#
# serverlib — aggregator for the SteamCMD dedicated-server helper library.
#
# Source THIS to get the whole library (the game installers do), or source an
# individual lib/serverlib/<module>.sh to pull only what you need — each module
# sources its own dependencies and is safe to source more than once.
#
# Modules:
#   log.sh       logging + set_tag
#   util.sh      sed_escape, gen_password, detect_ip, run_as, load_env
#   preflight.sh require_root, require_systemd
#   host.sh      install_base_deps, create_service_user, allow_ports
#   steamcmd.sh  install_steamcmd, steam_app_update, link_steamclient
#   systemd.sh   render_systemd_unit, install_systemd_service
#   helpers.sh   write_update_script, write_backup_script
#
# Functions live under the `serverlib::` namespace. The sourcing script is
# expected to run under `set -euo pipefail`.

# shellcheck source=serverlib/log.sh
source "${BASH_SOURCE[0]%/*}/serverlib/log.sh"
# shellcheck source=serverlib/util.sh
source "${BASH_SOURCE[0]%/*}/serverlib/util.sh"
# shellcheck source=serverlib/preflight.sh
source "${BASH_SOURCE[0]%/*}/serverlib/preflight.sh"
# shellcheck source=serverlib/host.sh
source "${BASH_SOURCE[0]%/*}/serverlib/host.sh"
# shellcheck source=serverlib/steamcmd.sh
source "${BASH_SOURCE[0]%/*}/serverlib/steamcmd.sh"
# shellcheck source=serverlib/systemd.sh
source "${BASH_SOURCE[0]%/*}/serverlib/systemd.sh"
# shellcheck source=serverlib/helpers.sh
source "${BASH_SOURCE[0]%/*}/serverlib/helpers.sh"
