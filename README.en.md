# BVN FPS Unlock

Frame-rate unlock plugin for **Bleach vs. Naruto** (the 5DPLAY competitive edition,
Adobe AIR 50.2 captive runtime, tested on v3.8.8.6).

[Chinese documentation](README.md)

> Unofficial fan-made tool. Not affiliated with 5DPLAY. This repository contains
> no game assets, no game code and no decrypted game data — only the plugin
> source, build scripts and reverse-engineering notes.

## What it does

- Raises the game frame rate from the stock 30/60 cap to any value in 20–480.
- Simulation speed stays correct: the engine is already frame-rate independent
  (`SPEED_PLUS = 30 / FPS_GAME`, all hold/delay constants scale with `FPS_GAME`),
  so the plugin drives `GameConfig.FPS_GAME`, `stage.frameRate` and
  `MainGame.setFPS()` together, every frame.
- **Netplay-safe**: during LAN/online matches the engine locks to 30 fps
  lockstep (`LockFrameLogic`). The plugin detects an active match and suspends
  itself completely (HUD shows `NETPLAY LOCK`).
- Installs through the game's own plugin system — one `.swf` dropped into
  `assets/plugin/`, nothing else modified.

## Install

1. Get `fps_unlock.swf` from
   [Releases](https://github.com/Ser1oux/bvn-fps-unlock/releases) (or `dist/`
   in this repo), and copy it to `<game>\assets\plugin\fps_unlock.swf`.
2. Start the game. The plugin activates automatically at menu init
   (`CONFIG.isRunBack = true`); a green HUD appears top-left.
3. If the game was already running, restart it once — plugins register at
   startup only.

To uninstall: delete or rename `assets\plugin\fps_unlock.swf`.

## Controls

| Key | Action |
|---|---|
| F1 | toggle HUD |
| F2 / F3 | target +15 / −15 (Shift: ±1) |
| F4 | toggle unlock / restore stock 60 |
| F5 | cycle presets 30/60/90/120/144/165/240 |
| F6 | dump live decrypted roster (dev) |

Target, unlock state and HUD visibility persist in `SharedObject("fps_unlock")`.

## Verify

Run `python tools/readsol.py` while the game is running. It reads the plugin's
plain-text telemetry (`%APPDATA%\com.1212321.bvn.sports\Local
Store\fps_unlock_status.txt`, written twice a second) and asserts
`engine == target`, `stage == target` and `speed_plus == 30 / target`.

## Building from source

Requires Apache Flex SDK 4.16+ (`mxmlc`) and a Java 8+ runtime. The SDK's
`frameworks/libs/player/32.0/playerglobal.swc` must exist (download
`playerglobal32_0.swc` from Adobe's updater archive if your SDK lacks it).

```powershell
$env:FLEX_SDK = "C:\path\to\flex-sdk"     # bin/mxmlc.bat
$env:JAVA_HOME = "C:\path\to\jre"         # optional, must be on PATH otherwise
.\tools\build.ps1
```

Output: `dist/fps_unlock.swf`.

Note: `<strict>false</strict>` is required — the plugin calls engine members
through `Class`-typed variables resolved at runtime (`getDefinitionByName`),
which strict mode rejects.

## How it works

See [docs/REVERSE_ENGINEERING.md](docs/REVERSE_ENGINEERING.md) for the full
reverse-engineering write-up: the three stock FPS caps, the `IS_LOW_QUALITY`
double-tick trap, the plugin injection point, and the netplay lockstep guard.

## Caveats

- This is the competitive (ranked) build; it uploads match records. The shipped
  `debugger+.swf` only sanctions 30/60 fps, so keep the unlock off (F4) for
  ranked/online play.
- Your monitor refresh rate is the real ceiling: on a 120 Hz display, targets
  above 120 render no extra visible frames.
- The per-frame hook swallows all exceptions by design: an escaping error in a
  high-priority `ENTER_FRAME` listener would abort the engine's own render pump.

## License

MIT — see [LICENSE](LICENSE).
