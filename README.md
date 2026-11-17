# Samurai Hook on Roblox

This repository is the Roblox port of [Samurai Hook](https://github.com/yurtemre7/samurai-hook). It is used as a git submodule at `roblox/` in that repository, and every command below runs from the parent repository's root. The test tools also read the web game's sources there.

To get both repositories, clone with submodules:

```bash
git clone --recurse-submodules https://github.com/yurtemre7/samurai-hook.git
```

Licence: PolyForm Noncommercial 1.0.0, the same as the web game (see `LICENSE`). Asset credits are in the parent repository's `CREDITS.md`.

A Roblox port of the web game in `src/`. It is the same 2D game, drawn on a 960x540 GUI canvas that scales to fit the screen. The fight simulation, state and tuning are line-for-line Luau copies of `src/fight/sim.ts`, `src/game/state.ts` and `src/manifest.ts`.

## Layout

| Path | Roblox location | What |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.SamuraiHook` | `Manifest` (tuning, fish, text), `State` (gold, upgrades), `Sim` (the fight), `Assets` (asset IDs) |
| `src/client/` | `StarterPlayerScripts.SamuraiHookClient` | Game loop, `Draw` (pooled GUI drawing), `Input`, `Audio`, `Hud`, `Settings`, `TouchButtons`, `Scenes/` |
| `src/server/` | `ServerScriptService.SamuraiHookServer` | The save server. It owns gold and upgrades and saves them to a DataStore. It checks purchases, rate limits requests, and allows one sale per fight, only for a fish the line can reach and only after the shortest possible fight time. It does not check that the fight was really won: the fight runs on the client |

## Run it

1. Start Rojo from this folder:

   ```bash
   rojo serve roblox/default.project.json
   ```

2. Open Roblox Studio and create a new Baseplate place.
3. Open the **Plugins** tab, click **Rojo** and then **Connect**.
4. Press **Play**.

Or build a place file and open it in Studio:

```bash
rojo build roblox/default.project.json -o roblox/SamuraiHook.rbxlx
```

**Saving:** the DataStore only works in a place that is published. It also needs **Game Settings > Security > Enable Studio Access to API Services** turned on. Without that, progress lasts for the session only, and the Output window shows a warning.

**Studio shortcuts:** F2 loads the demo progress and F4 wipes the save. Both work in Studio only.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Move, steer the hook | A D / arrow keys | Stick, D-pad | Drag (ocean), ◀ ▶ (fight) |
| Jump, duck | W / S | Up / down | JUMP / DUCK |
| Quick slash | J, left click | X | QUICK |
| Heavy slash | K, right click | Y | HEAVY |
| Block (hold), dash (tap with a direction) | L, Left Shift | B, RB | BLOCK |
| Confirm, drop hook | Space, Enter, click the water | A | Tap the water |
| Shop | E | Y | Tap SHOP in the prompt bar |
| Pause, settings | **Tab or P** (Roblox reserves Esc) | Select | Tap PAUSE / SETTINGS |

Every prompt-bar item can be clicked or tapped.

## Art and sound

The game runs without any assets. It draws placeholder shapes and plays no sound. `roblox/tools/upload-assets.mjs` uploads the real art and sound with the Open Cloud Assets API and writes the IDs to `src/shared/AssetIds.luau`. Rojo then syncs them into Studio.

One-time setup:

1. On [create.roblox.com](https://create.roblox.com), go to **Open Cloud > API Keys > Create API Key**.
2. Under **Access Permissions**, add the **Assets** API with **Read** and **Write**.
3. Under **Accepted IP Addresses**, add your own IP address, or `0.0.0.0/0` to allow any address. Then save and copy the key.
4. Find your user ID: it's the number in your profile URL, `roblox.com/users/<id>/profile`.
5. Store both values in PowerShell. Type the key yourself; nothing in this repo stores it.

   ```powershell
   [Environment]::SetEnvironmentVariable("ROBLOX_API_KEY", "<your key>", "User")
   ```

   ```powershell
   [Environment]::SetEnvironmentVariable("ROBLOX_USER_ID", "<your user id>", "User")
   ```

6. Open a new terminal, then run:

   ```bash
   node roblox/tools/upload-assets.mjs --dry-run
   ```

   ```bash
   node roblox/tools/upload-assets.mjs
   ```

The script remembers each upload in `roblox/upload/uploaded.json` by file content, so running it again sends only new or changed files.

Sounds go most important first: music, fight sounds, UI, then the announcer. Accounts without ID verification may upload only 10 sounds a month. When that limit is reached, the script stops and keeps the IDs it already has; run it again next month to continue. `--images` uploads the images only.

Roblox moderates every upload. If the upload API returns a Decal instead of an Image, the server looks up the image inside the decal when the game starts.

To upload by hand instead, use Studio's **Asset Manager > Bulk Import** on the files in `roblox/upload/` (made by `node roblox/tools/make-upload.mjs`). Then paste each ID into `src/shared/Assets.luau`.

**Credits:** the licences are listed in the top-level `CREDITS.md`. The "Fight" voice line is CC-BY 4.0 (Alba MacKenna), so credit her in the game description if you upload it.

## Tests

The tests run outside Studio with [Lune](https://github.com/lune-org/lune):

```bash
npx vite-node roblox/tools/dump-traces.ts
```

```bash
lune run roblox/tests/sim.spec.luau
```

```bash
lune run roblox/tests/scenes.spec.luau
```

- `dump-traces.ts` records 54 fights from the TypeScript sim: every fish, both modes, three bots.
- `sim.spec.luau` replays those fights in the Luau sim and checks that every step matches.
- `scenes.spec.luau` plays every scene with mocked GUI and input, to catch runtime errors.

After any change to `src/manifest.ts` or `src/fight/sim.ts`, copy the change into the Luau files and run `sim.spec` again.

## Differences from the web build

- The art is simpler: gradients and shapes stand in for the canvas paintings. The anglerfish darkness is drawn in tiles, because GUI objects cannot cut holes.
- There is no key rebinding page in the settings, and no speech synthesis (an announcer line without a clip is silent).
- Pause is on Tab or P, because Esc opens the Roblox menu.
- Progress is saved on the server, not in localStorage. There is no session locking (see the note in `src/server/init.server.luau`).
