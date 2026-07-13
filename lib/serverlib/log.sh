#!/usr/bin/env bash
# Logging helpers. Games set the prefix via serverlib::set_tag. No dependencies.
if [[ -n "${_SERVERLIB_LOG:-}" ]]; then return 0; fi
_SERVERLIB_LOG=1

serverlib::log()  { printf '\033[1;36m[%s]\033[0m %s\n' "${SERVERLIB_TAG:-server}" "$*"; }
serverlib::warn() { printf '\033[1;33m[%s]\033[0m %s\n' "${SERVERLIB_TAG:-server}" "$*" >&2; }
serverlib::die()  { printf '\033[1;31m[%s]\033[0m %s\n' "${SERVERLIB_TAG:-server}" "$*" >&2; exit 1; }

# Set the tag shown in log prefixes. Call once from a game script.
serverlib::set_tag() { SERVERLIB_TAG="$1"; }
