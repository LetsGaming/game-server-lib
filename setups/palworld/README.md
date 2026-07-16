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

## Difficulty presets

`options.conf` (the default) is deliberately **not** vanilla — all-`1.0` rates are trivial once you know Palworld, so it ships a harder-but-fair baseline. Progression stays at `1.0` (no added grind); the changes target lethality, death stakes, and upkeep:

| Setting | Value | vanilla | Effect |
|---|---|---|---|
| `PlayerDamageRateDefense` | `2.0` | 1.0 | you take **2× damage** — combat is actually dangerous (the Hard preset's 4× is widely seen as overtuned) |
| `PalDamageRateDefense` | `1.5` | 1.0 | your Pals are 1.5× more fragile, so a tanky Pal can't facetank everything |
| `DeathPenalty` | `ItemAndEquipment` | `Item` | death drops items **and equipment** (Pals kept) — recovering your gear is the tension, short of permadeath |
| `PlayerStomachDecreaceRate` | `1.2` | 1.0 | hunger drains faster |
| `PlayerStaminaDecreaceRate` | `1.2` | 1.0 | stamina drains faster |
| `PalStomachDecreaceRate` | `1.2` | 1.0 | Pals get hungry faster — base food logistics matter |

Higher `...DamageRateDefense` = more damage taken (counterintuitive, but confirmed: `0.5` = half damage, `2.0` = double). Leave `Difficulty=None` — it means "use these custom values"; setting a named preset can override them.

### Harder preset — `options.hard.conf`

If medium still isn't biting, switch presets in `.env` and re-run `reset.sh`:

```bash
OPTIONS_FILE="options.hard.conf"     # in .env
sudo ./reset.sh
```

The design goal is **harder without "one misstep and you're dead"**. Cranking `PlayerDamageRateDefense` to the stock Hard preset's `4.0` is exactly what produces that — a hit that does ~200 on vanilla lands for ~800 and two-shots you. So this preset stops at `2.5` and spreads the difficulty across more axes instead: fights run longer, recovery is slow, upkeep is real, raids bite.

| Setting | medium | hard | Effect |
|---|---|---|---|
| `PlayerDamageRateDefense` | 2.0 | **2.5** | more incoming damage — still short of two-shot territory |
| `PalDamageRateDefense` | 1.5 | **2.0** | Pals are genuinely fragile; no facetanking |
| `PlayerDamageRateAttack` | 1.0 | **0.8** | you deal less, so fights last longer — raises time-to-kill instead of cutting time-to-die |
| `PlayerAutoHPRegeneRate` | 1.0 | **0.5** | no passive heal-tanking; food and meds matter |
| `PlayerAutoHpRegeneRateInSleep` | 1.0 | **0.5** | sleeping isn't a free full reset |
| `PalAutoHPRegeneRate` / `...InSleep` | 1.0 | **0.5** | hurt Pals stay hurt |
| `PlayerStomachDecreaceRate` | 1.2 | **1.5** | hunger is a real clock |
| `PlayerStaminaDecreaceRate` | 1.2 | **1.5** | stamina pressure in fights and traversal |
| `PalStomachDecreaceRate` | 1.2 | **1.5** | base food logistics matter |
| `PalStaminaDecreaceRate` | 1.0 | **1.3** | Pals tire |
| `PalSpawnNumRate` | 1.0 | **1.2** | denser world, fewer safe gaps |
| `BuildObjectDamageRate` | 1.0 | **1.5** | raids actually threaten the base |

Deliberately **not** changed: `DeathPenalty` stays `ItemAndEquipment` (going to `All` loses your Pals too and invites a death spiral — losing the fight that killed you shouldn't cost you the means to fight back); `bHardcore` / `bPalLost` stay off (that *is* one-misstep-death); and XP, capture, gathering, work speed, and hatching all stay at `1.0` — this is meant to be harder, not grindier. `PalDamageRateAttack` is untouched because it scales *all* Pals, yours included, so the net direction is ambiguous.

Dial it: too spicy → `PlayerDamageRateDefense` back to `2.0`, or regen back to `1.0`. Still soft → `3.0` is the ceiling I'd go to before it turns spiky. Want actually brutal → `4.0` plus `bHardcore=True` / `DeathPenalty=All`, but that's the thing this preset exists to avoid.

**Existing worlds:** on world creation Palworld writes `WorldOption.sav` into the save and from then on it silently overrides `PalWorldSettings.ini`. These settings apply cleanly to a **new** world; to change one that already exists, back up the save, then delete `WorldOption.sav` (in `.../Pal/Saved/SaveGames/0/<world-id>/`) so the `.ini` is read again.

## Resetting / applying changed settings

Editing `options.conf` or `.env` does **nothing** to a running server on its own: `install.sh` won't overwrite an existing `PalWorldSettings.ini`, and Palworld writes a `WorldOption.sav` into the save at world creation that from then on silently overrides the `.ini`. `reset.sh` handles both.

```bash
sudo ./reset.sh                     # re-apply settings, KEEP the world
sudo ./reset.sh --wipe-world        # ...and start a brand-new world
sudo ./reset.sh --wipe-world --yes  # skip the confirmation prompt
```

It stops the server, takes a backup, deletes the generated `.ini` (and `WorldOption.sav`, or the whole save with `--wipe-world`), regenerates the config from `options.conf` + `.env`, syncs mods, and starts back up. It does **not** re-run SteamCMD, so it takes seconds. A `--wipe-world` asks for confirmation unless you pass `--yes`.

Your admin password survives a reset: `.env` wins if set, otherwise the existing config's password is reused rather than regenerated.

Settings baked in at world creation (the seed, for one) still won't budge without `--wipe-world`.

## Mods

Short version: **server-side mods barely work on Linux**, and that's Pocketpair's position, not a limitation of these scripts — the 1.0 server docs say server-side mods work only on the Windows dedicated server. The official loader (`PalModSettings.ini` / `ActiveModList` / Workshop packages) and UE4SS-based mods (including PalSchema) are Windows-only.

Plain `.pak` content mods are the one thing that can still work, since Unreal loads them itself. Drop them in `mods/` and run `./reset.sh`. That folder is the source of truth — removing a `.pak` and re-running removes it from the server too, which matters because Pocketpair require old mods to be *deleted* before a game update, not just disabled.

Read `mods/README.md` before you spend time on it. Most of what mods are used for (rates, difficulty, capture, drops, base limits) is in `options.conf` already and works properly.

## Important for Palworld

- **The memory leak is real — schedule a daily restart, don't buy RAM to outrun it.** The process climbs in memory over long uptimes and will eventually OOM (often after ~5–7 days) regardless of how much RAM you throw at it. Add the cron line the installer prints: `0 5 * * * root systemctl restart palworld`. A restart takes seconds and players reconnect to the same world.
- **Cap per-base load to keep memory predictable.** Each base full of working Pals is a continuous simulation cost. Setting `BaseCampWorkerMaxNum` to ~15–20 in `PalWorldSettings.ini` bounds it.
- **Only `PalWorldSettings.ini` matters** for server settings (not `Game.ini`). Palworld requires the whole `OptionSettings=(...)` on a single line, so you don't edit that file directly — instead edit `options.conf` (one setting per line, with comments and sections), and the installer compiles it into the single-line `.ini` and patches in your `.env` values. Change `options.conf` to set the defaults future servers get; regenerate an existing one as described above (stop, delete the `.ini`, re-run).
- **Crossplay is supported on 1.0.** To let Steam/Xbox/PS5/Mac players in, ensure `CrossplayPlatforms=(Steam,Xbox,PS5,Mac)` is set in the config.
- **Legacy (0.x) saves are a gamble on 1.0.** The overhauled world generation raises CPU/RAM/disk pressure, and forced-converted saves are more prone to corruption. Pocketpair suggests starting fresh; if you must keep an old save, back it up first.
- **Update after every patch** with `palworld-update`. Clients auto-update and get a version-mismatch error until the server matches. Patches sometimes add new `PalWorldSettings.ini` keys with defaults you may not want — back up the config before updating.
- **Ports:** only `8211/udp` (the game port) must be reachable. The optional REST admin API (`8212/tcp`) and RCON are left off by this setup. Behind CGNAT, port-forwarding from home won't work — compare your router's WAN IP with whatismyip.com to check.
