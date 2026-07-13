# game-server-lib

Reusable Debian setup scripts for SteamCMD-based dedicated game servers, built on a small shared bash library. Designed to run on a clean Proxmox Debian VM.

```
game-server-lib/
├── palworld.sh         # Palworld 1.0   (Steam app 2394010)
├── ark-se.sh           # ARK: Survival Evolved (Steam app 376030)
├── lib/
│   └── serverlib.sh    # shared logic (deps, user, SteamCMD, systemd, firewall, helpers)
├── .gitlab-ci.yml      # shellcheck lint on push
├── .editorconfig
├── .gitattributes      # force LF for scripts
├── .gitignore
├── LICENSE
└── README.md
```

Installers live in the repo root; everything they share sits in `lib/`.

Each game script is a thin config layer: it sets a handful of variables, then calls library functions in order. All logic the games share lives in `lib/serverlib.sh`, so a fix or improvement lands in one place for every game.

## Quick start

Copy the whole folder onto the VM (keep the `lib/` subfolder next to the scripts), then:

```bash
# Palworld
nano palworld.sh        # edit the "EDIT THESE" block at the top
sudo ./palworld.sh

# ARK: Survival Evolved
nano ark-se.sh
sudo ./ark-se.sh
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

## VM sizing

| Game | RAM | vCPU | Disk |
|------|-----|------|------|
| Palworld 1.0 | 16 GB recommended (8 GB for small groups) | 4 | ~20 GB |
| ARK: Survival Evolved | 8–16 GB (more with mods / large maps) | 4 | ~30 GB |

Both are memory-hungry and prone to memory growth over long uptimes — a daily restart via cron is a good idea (see each script's summary).

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

## Adding a new game

Copy an existing game script and adjust three things — you rarely touch the library:

1. **The `EDIT THESE` block** — name, passwords, ports, install dir, service user.
2. **The Steam `APPID`** and the **launch command** (`ExecStart`). Some games (Palworld) read an INI you patch; others (ARK) read settings straight off the command line.
3. **The port list** passed to `serverlib::allow_ports` and the **save path** passed to `serverlib::write_backup_script`.

The library gives you these building blocks:

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
| `serverlib::render_systemd_unit ...` | pure unit renderer (no writes — used by the installer, handy for testing) |

Set `SERVERLIB_TAG="<game>"` so log lines are prefixed with the game name.

## Development

Shell scripts are linted with [ShellCheck](https://www.shellcheck.net/). Run it locally before committing:

```bash
shellcheck -x lib/serverlib.sh palworld.sh ark-se.sh
```

`.gitlab-ci.yml` runs the same check on every push. `.editorconfig` and `.gitattributes` keep formatting and line endings consistent (LF — bash breaks on CRLF).

## Notes

- ARK here is **Survival Evolved** (native Linux server, app 376030), **not** Survival Ascended, whose dedicated server is Windows-only.
- The scripts target Debian 12/13 and expect `systemd`. They run everything under a dedicated unprivileged user; nothing runs as root except the installer itself.
