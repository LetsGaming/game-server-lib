#!/usr/bin/env bash
# General-purpose helpers with no side effects on other modules. No dependencies.
if [[ -n "${_SERVERLIB_UTIL:-}" ]]; then return 0; fi
_SERVERLIB_UTIL=1

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

# Run a command as the service user (with its HOME from /etc/passwd).
# usage: serverlib::run_as USER CMD [ARGS...]
serverlib::run_as() {
  local user="$1"; shift
  sudo -u "$user" -H "$@"
}

# Load KEY=VALUE pairs from a file into shell variables WITHOUT executing it as
# a script. Values are taken literally, so passwords or names containing $, !,
# quotes, or backticks are safe (sourcing them would expand or even run them).
# One layer of matching surrounding quotes is stripped; comments and blank lines
# are ignored; a missing file is a no-op.
# usage: serverlib::load_env FILE
serverlib::load_env() {
  local file="$1" line key val first last
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"                                   # tolerate CRLF
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue      # blank / comment line
    line="${line#export }"                                 # allow an "export " prefix
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue   # valid identifier only
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"                   # trim leading whitespace
    val="${val%"${val##*[![:space:]]}"}"                   # trim trailing whitespace
    if [[ ${#val} -ge 2 ]]; then                           # strip one matching quote layer
      first="${val:0:1}"; last="${val: -1}"
      if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
        val="${val:1:-1}"
      fi
    fi
    printf -v "$key" '%s' "$val"                           # assign literally (no expansion)
  done < "$file"
}
