# game-server-lib

Reusable Debian setup scripts for SteamCMD-based dedicated game servers, built on a small shared bash library. Designed to run on a clean Proxmox Debian VM. Configuration is per-game via a `.env` file — you never edit the scripts.

```
game-server-lib/
├── setups/
│   ├── palworld/
│   │   ├── install.sh       # Palworld 1.0   (Steam app 2394010)
│   │   ├── reset.sh         # re-apply settings / wipe the world
│   │   ├── common.sh        # config + paths shared by install.sh and reset.sh
│   │   ├── .env.example     # copy to .env and edit
│   │   ├── options.conf     # editable world settings (compiled into the .ini)
│   │   ├── options.hard.conf # harder preset — select via OPTIONS_FILE in .env
│   │   ├── mods/            # drop .pak mods here (Linux support is limited)
│   │   └── README.md        # Palworld sizing + gotchas
│   └── ark-se/
│       ├── install.sh       # ARK: Survival Evolved (Steam app 376030)
│       ├── .env.example
│       ├── gameusersettings.conf  # editable rates & difficulty (→ GameUserSettings.ini)
│       ├── game.conf              # editable breeding & advanced (→ Game.ini)
│       └── README.md        # ARK sizing + gotchas
├── lib/
│   ├── serverlib.sh         # barrel: source this for everything
│   └── serverlib/           # modules — source one for just what you need
│       ├── log.sh           # logging + set_tag
│       ├── util.sh          # sed_escape, gen_password, detect_ip, run_as, load_env
│       ├── preflight.sh     # require_root, require_systemd
│       ├── host.sh          # install_base_deps, create_service_user, allow_ports
│       ├── steamcmd.sh      # install_steamcmd, steam_app_update, link_steamclient
│       ├── systemd.sh       # render_systemd_unit, install_systemd_service
│       └── helpers.sh       # write_update_script, write_backup_script
├── .github/
│   └── workflows/
│       └── shellcheck.yml   # lints the scripts on push
├── .editorconfig
├── .gitattributes           # force LF (bash breaks on CRLF)
├── .gitignore               # ignores .env
├── LICENSE
└── README.md
```

Each `install.sh` is a thin layer: it loads config from `.env`, then calls library functions in order. Everything the games share lives in `lib/serverlib/` (with `lib/serverlib.sh` re-exporting it all), so a fix lands in one place for every game.

## Quick start

Copy the repo onto the VM, then per game:

```bash
cd setups/palworld          # or setups/ark-se
cp .env.example .env        # edit .env to taste (defaults also work as-is)
nano .env
sudo ./install.sh
```

Each installer:

1. Installs SteamCMD dependencies (enables the i386 architecture).
2. Creates an unprivileged, non-login service user.
3. Installs the server via SteamCMD (anonymous — you don't need to own the game to host).
4. Creates the `steamclient.so` symlinks that otherwise break the first launch.
5. Applies your settings (Palworld: `PalWorldSettings.ini`; ARK: the launch command).
6. Installs a `systemd` service (auto-start on boot, auto-restart on crash).
7. Installs `<game>-update` and `<game>-backup` helpers in `/usr/local/bin`.
8. Opens the required ports in `ufw` if it's active.

Re-running an installer is safe.

## Configuration (`.env`)

All tunables live in each game's `.env`. The workflow:

- `.env.example` is committed and holds the **default values** (documented inline).
- `install.sh` sources `.env.example` first (defaults), then sources `.env` if present, so your `.env` only needs the values you want to change. Running without a `.env` uses the defaults.
- `.env` is gitignored — it may hold your admin password, so it never gets committed.

Leaving `ADMIN_PASSWORD` empty auto-generates a strong one and prints it at the end.

## VM sizing

| Game | RAM | vCPU | Disk |
|------|-----|------|------|
| Palworld 1.0 | 16 GB recommended (8 GB for small groups) | 4 | ~20 GB |
| ARK: Survival Evolved | 8–16 GB (more with mods / large maps) | 4 | ~30 GB |

Both are memory-hungry and grow over long uptimes — a daily restart via cron is a good idea (see each script's summary). For small/medium/large tiers and game-specific tuning, see each game's own README: [Palworld](setups/palworld/README.md), [ARK: SE](setups/ark-se/README.md).

## Ports (open these at the Proxmox / router firewall too if the VM is behind NAT)

| Game | Ports |
|------|-------|
| Palworld | `8211/udp` |
| ARK: SE | `7777/udp`, `7778/udp`, `27015/udp` (RCON `27020/tcp` only if you enable it) |

All game traffic here is **UDP** — opening only TCP is the classic reason a healthy server looks unreachable.

## Per-game helpers

Installed into `/usr/local/bin`, run as root:

- `palworld-update` / `ark-se-update` — stop, pull the latest server build, restart. Run after every game patch (clients auto-update and get "connection timed out" until the server version matches).
- `palworld-backup` / `ark-se-backup` — tar the save directory into `<base>/backups`, keeping the 14 most recent. Saves can corrupt, so back up before updates.

## Editing config later

Both games rewrite parts of their config on shutdown, so **stop the service before editing**:

```bash
sudo systemctl stop palworld     # or ark-se
# edit the config
sudo systemctl start palworld
```

- Palworld: `/opt/palworld/server/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini`
- ARK: `/opt/ark-se/server/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini` and `Game.ini` (generated on first boot)

Note: changing ports or player counts is easiest by editing `.env` and re-running `install.sh`.

## Adding a new game

Copy an existing game folder and adjust it — you rarely touch the library:

1. `cp -r setups/ark-se setups/<newgame>`
2. In `.env.example`, set the game's variables (name, ports, install dir, service user).
3. In `install.sh`, change the Steam `APPID`, the **launch command** (`ExecStart`), the **port list** passed to `serverlib::allow_ports`, and the **save path** passed to `serverlib::write_backup_script`.
4. Write a short `README.md` for the game (hardware tiers + gotchas), matching the existing two.
5. That's all for CI — the ShellCheck workflow lints every `*.sh` in the repo automatically, so there's no list to update.

The library provides these building blocks:

| Function | Purpose |
|----------|---------|
| `serverlib::require_root` / `require_systemd` | preflight checks |
| `serverlib::install_base_deps [pkg...]` | SteamCMD deps (+ optional extras) |
| `serverlib::create_service_user USER HOME` | non-login service account |
| `serverlib::install_steamcmd USER DIR` | download SteamCMD (idempotent) |
| `serverlib::steam_app_update USER STEAMCMD_DIR INSTALL_DIR APPID` | install/update a Steam app |
| `serverlib::link_steamclient USER HOME STEAMCMD_DIR` | the `steamclient.so` fix |
| `serverlib::install_systemd_service NAME DESC USER WORKDIR EXEC_START [EXEC_STOP]` | write + enable a unit |
| `serverlib::allow_ports "P/proto"...` | open firewall ports |
| `serverlib::write_update_script ...` / `write_backup_script ...` | generate helpers |
| `serverlib::gen_password [len]` / `sed_escape STR` / `detect_ip` | small utilities |
| `serverlib::render_systemd_unit ...` | pure unit renderer (no writes — handy for testing) |

Call `serverlib::set_tag "<game>"` so log lines are prefixed with the game name. Sourcing `lib/serverlib.sh` gives you every function above; to pull only some, source individual `lib/serverlib/<module>.sh` files (each loads its own dependencies).

## Development

Shell scripts are linted with [ShellCheck](https://www.shellcheck.net/). Run it locally before committing:

```bash
find . -name '*.sh' -print0 | xargs -0 -r shellcheck -x
```

`.github/workflows/shellcheck.yml` runs the same check on every push. `.editorconfig` and `.gitattributes` keep formatting and line endings consistent.

## Notes

- ARK here is **Survival Evolved** (native Linux server, app 376030), **not** Survival Ascended, whose dedicated server is Windows-only.
- The scripts target Debian 12/13 and expect `systemd`. They run everything under a dedicated unprivileged user; nothing runs as root except the installer itself.
