# ARK: Survival Evolved dedicated server

Setup for an **ARK: Survival Evolved** (ASE) dedicated server (SteamCMD app `376030`). ASE is the legacy Unreal Engine 4 build and has a **native Linux server**. This is *not* ARK: Survival Ascended (ASA, app `2430930`) — ASA runs on UE5, needs Wine/Proton on Linux, and demands roughly 3× the resources. See the [repo README](../../README.md) for the install workflow; this page covers sizing and ARK-specific behaviour.

## Hardware by server size

ARK **loads the entire map into RAM at startup** and grows from there as players build structures and tame dinos. On Linux the install sits around 3 GB idle and needs at least 6 GB to start. RAM is the primary bottleneck, and the map and mod list move the numbers as much as player count does.

| Size | Players | RAM | CPU | Disk |
|------|---------|-----|-----|------|
| **Small** | 2–5, TheIsland, vanilla | 8 GB | quad-core, 3.5 GHz+ | ~30 GB SSD |
| **Medium** | up to ~15, light mods | 12–16 GB | 4–6 cores, high clock | ~40–60 GB NVMe |
| **Large** | 20+, heavy mods / big maps | 16–32 GB | 6–8 cores, high clock | ~60–100 GB NVMe |

8 GB is the floor, not a comfortable target — anything beyond a small vanilla Island server wants 12 GB+. A world that starts at ~6 GB of usage can climb past 10 GB after a few weeks of active play.

**CPU: clock speed over core count.** The main simulation is largely single-threaded, so a modern 3.5 GHz+ core carries the game loop; extra cores mainly help background work like saving and mod loading. Budget roughly two cores per server.

**Storage: NVMe/SSD required.** ARK writes frequent autosaves and spikes memory while serializing the world to disk; a SATA SSD can stutter and a spinning disk is unusable.

## Difficulty & rates (tuned medium)

Two editable sources in this folder compile into the server's config: `gameusersettings.conf` → `GameUserSettings.ini [ServerSettings]`, and `game.conf` → `Game.ini [/script/shootergame.shootergamemode]`. The installer strips the comments and writes the real INIs. The tuning targets a **hard world with a casual grind** — veterans get danger and worthwhile tames, nobody loses an afternoon to a single tame.

| Setting | Value | File | Effect |
|---|---|---|---|
| `OverrideOfficialDifficulty` | `5.0` | GameUserSettings | wild dinos up to **level 150** — the real challenge (ARK's low defaults are why vanilla feels trivial) |
| `TamingSpeedMultiplier` | `3.0` | GameUserSettings | tames in a fraction of vanilla time, still a real tame |
| `HarvestAmountMultiplier` | `2.0` | GameUserSettings | less gathering grind |
| `XPMultiplier` | `2.0` | GameUserSettings | steady leveling |
| `EggHatchSpeedMultiplier` / `BabyMatureSpeedMultiplier` | `25.0` | Game.ini | a Rex raise drops from multi-day to an evening |
| `MatingIntervalMultiplier` / `BabyCuddleIntervalMultiplier` | `0.1` | Game.ini | breed often; cuddles keep pace for 100% imprint |
| `BabyImprintAmountMultiplier` | `3.0` | Game.ini | enough imprint per cuddle to actually cap out |

Combat multipliers are left at vanilla on purpose — the challenge comes from high-level wild dinos, not bullet-sponge enemies. Direction is mixed: **speed** multipliers go up to go faster, **interval** multipliers go down to go faster.

**Two-file gotcha:** breeding, imprint, and per-level multipliers **only work in `Game.ini`** — ARK silently ignores them in `GameUserSettings.ini`, and breeding stays on multi-day official rates no matter what you set. The split is already correct across the two `.conf` files; keep breeding keys in `game.conf`.

**Editing:** change a `.conf` file, then stop the service, delete the matching generated `.ini`, and re-run `install.sh`. ARK reads these only on boot, so a restart is required to apply.

**Existing worlds:** `OverrideOfficialDifficulty` only affects newly-spawned dinos. A fresh world spawns level-150 dinos immediately; on an existing world, run the admin command `DestroyWildDinos` once (or wait for natural respawns) so the map repopulates at the new levels.

## Important for ARK

- **First boot takes 5–15 minutes** (longer with mods) while the map, spawn tables, and creatures initialize. Watch `journalctl -u ark-se -f` and **do not restart during this** — let it finish.
- **The open-files limit is critical, and this setup handles it.** The systemd unit sets `LimitNOFILE=100000`. Without it, the server burns CPU without reaching ~5.5 GB RAM because it can't open all the files it needs.
- **`TamedDinoLimit` (in `Game.ini`) is your main RAM lever.** Tames stay in memory even when their owner is offline, so hundreds of dinos balloon usage. A value like 4000–5000 keeps a community server sane. Add it to `game.conf` (which generates `Game.ini`) and regenerate — see Difficulty & rates above.
- **Map choice drives resource use.** `TheIsland` is the lightest and the classic experience; `Ragnarok`, `Genesis`, and other large maps use noticeably more RAM. Set it via `MAP` in `.env` (changing it is easiest by editing `.env` and re-running `install.sh`).
- **Mods add RAM, CPU, and boot time.** ASE supports Steam Workshop mods; creature packs and overhaul mods are the heaviest. Size up before installing them (if you'd normally need 16 GB, plan 24 GB).
- **Clusters need per-map resources.** Each map in a cluster is a separate server process with its own RAM budget — size them individually.
- **Ports:** `7777/udp` (game), `7778/udp` (peer, = game port + 1), and `27015/udp` (Steam query) must be reachable; the installer opens all three. RCON (`27020/tcp`) is left off. Note: the query port must **not** fall in `27020–27050` (Steam reserves that range) — the default `27015` is fine.
- **Epic/crossplay (optional):** to let Epic Games players join, launch with `-crossplay` and `-PublicIPForEpic=<your-public-ip>`.
- **Update after every patch** with `ark-se-update`; clients get a version-mismatch error until the server matches.
