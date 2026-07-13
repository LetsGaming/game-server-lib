# Palworld dedicated server

Setup for a Palworld 1.0 dedicated server (SteamCMD app `2394010`). Palworld ships a **native Linux server**, so no Wine/Proton layer is needed. See the [repo README](../../README.md) for the install workflow; this page covers sizing and Palworld-specific behaviour.

## Hardware by server size

Palworld's server is heavier than its art style suggests, and RAM scales with **player count, base sprawl, and uptime** — not slots alone. A 5-player server with sprawling bases full of working Pals can use more RAM than a 24-player server with small ones.

| Size | Players | RAM | CPU | Disk |
|------|---------|-----|-----|------|
| **Small** | up to ~6 | 8 GB (16 GB safer) | fast quad-core, 3.5 GHz+ | ~20–40 GB SSD |
| **Medium** | up to ~16 | 16 GB | 4–6 cores, high clock | ~40–60 GB NVMe |
| **Large** | up to 32 / busy / modded | 32 GB | 6–8 cores, high clock | ~60–100 GB NVMe |

Pocketpair officially recommends 16 GB even for small servers because memory use climbs over time. 8 GB boots and works for a handful of players *if* you schedule restarts and keep bases modest.

**CPU matters more than core count.** The simulation — Pal AI, base automation, breeding, production lines — leans hard on single-thread performance and uses only about two cores. A modern high-clock quad-core beats an older many-core server chip. If the server lags as your group builds more automation, the CPU is usually the bottleneck, not RAM.

**Storage: SSD/NVMe is non-negotiable.** Pocketpair warns that slow disks can corrupt save data, and frequent autosaves stutter on a spinning disk.

## Important for Palworld

- **The memory leak is real — schedule a daily restart, don't buy RAM to outrun it.** The process climbs in memory over long uptimes and will eventually OOM (often after ~5–7 days) regardless of how much RAM you throw at it. Add the cron line the installer prints: `0 5 * * * root systemctl restart palworld`. A restart takes seconds and players reconnect to the same world.
- **Cap per-base load to keep memory predictable.** Each base full of working Pals is a continuous simulation cost. Setting `BaseCampWorkerMaxNum` to ~15–20 in `PalWorldSettings.ini` bounds it.
- **Only `PalWorldSettings.ini` matters** for server settings (not `Game.ini`). Stop the service before editing it — the server rewrites parts on shutdown.
- **Crossplay is supported on 1.0.** To let Steam/Xbox/PS5/Mac players in, ensure `CrossplayPlatforms=(Steam,Xbox,PS5,Mac)` is set in the config.
- **Legacy (0.x) saves are a gamble on 1.0.** The overhauled world generation raises CPU/RAM/disk pressure, and forced-converted saves are more prone to corruption. Pocketpair suggests starting fresh; if you must keep an old save, back it up first.
- **Update after every patch** with `palworld-update`. Clients auto-update and get a version-mismatch error until the server matches. Patches sometimes add new `PalWorldSettings.ini` keys with defaults you may not want — back up the config before updating.
- **Ports:** only `8211/udp` (the game port) must be reachable. The optional REST admin API (`8212/tcp`) and RCON are left off by this setup. Behind CGNAT, port-forwarding from home won't work — compare your router's WAN IP with whatismyip.com to check.
