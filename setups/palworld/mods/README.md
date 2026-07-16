# Palworld mods — read this before you bother

**Server-side mods barely work on Linux.** Pocketpair's 1.0 server docs are blunt: *"At this time, server-side mods work only on the dedicated server with Windows edition."* This server runs the Linux binary, so:

- **The official mod loader does not run here.** No `PalModSettings.ini`, no `ActiveModList`, no Workshop packages, no `Info.json` / `InstallRules` deployment. That whole system is Windows-only.
- **UE4SS mods don't run here.** UE4SS works by injecting a Windows DLL. PalSchema (the JSON data-tweak framework most 2026 server mods now use) sits on top of UE4SS, so it's out too.
- **Plain `.pak` content mods are the only thing that might work**, because Unreal itself loads them — no loader involved. This folder covers exactly that case and nothing else.

Before spending time here: most of what people install mods for (rates, difficulty, capture, drops, base limits) is already in `../options.conf` and works properly. Reach for that first.

## Using it

1. Download a mod (Nexus Mods, CurseForge, Thunderstore, palmods.gg) and extract the `.pak` out of the archive.
2. Check it's actually usable: the mod must be a **plain `.pak`**, and it must be **server-side** (the description says server-side, or its `Info.json` has `"IsServer": true`). If the page mentions UE4SS, RE-UE4SS, PalSchema, Lua, or `.dll`, stop — it will not work on Linux.
3. Confirm it lists **Palworld 1.0** compatibility. 1.0 broke essentially every earlier mod.
4. Drop the `.pak` in this folder.
5. Apply it: `sudo ../reset.sh` (backs up, regenerates config, restarts).

This folder is the source of truth. `install.sh` and `reset.sh` mirror it into `Pal/Content/Paks/~mods/` — so **deleting a `.pak` here and re-running removes it from the server**. That matters: Pocketpair require old mods to be *deleted* (not just disabled) before a game update.

## Rules of thumb

- **One at a time.** Add a mod, restart, confirm the server boots and players connect, then add the next.
- **If the server won't boot after an update, mods are suspect number one.** Empty this folder, re-run `reset.sh`, confirm vanilla boots.
- **Same version, same mods, or nobody joins.** Clients that don't match get "connection timed out". Client-side mods will also break crossplay on a mixed Steam/Xbox/PS5 server.
- **Console players can't install mods at all** — they can still join if every mod is server-side only.
- **Back up first.** Mods can corrupt saves; that's Pocketpair's own warning, not FUD.

`.pak` files are gitignored, so they stay out of the repo (they're third-party binaries). Drop them per-VM, or remove the `mods/*.pak` line from `.gitignore` if you'd rather version your mod set.

## If you actually need mods

Run the **Windows** dedicated server — that's the only supported path today. On this Proxmox host that means a Windows VM rather than the Linux one. Running the Windows server under Wine/Proton on Linux is a known workaround, but it's finicky and stability-caveated; don't put a world you care about on it.
