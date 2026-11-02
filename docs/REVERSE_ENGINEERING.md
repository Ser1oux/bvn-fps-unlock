# Reverse-engineering notes

Target: `Bleach vs. Naruto.exe` (死神vs火影 竞技版) v3.8.8.6, Adobe AIR / Harman
runtime 50.2 captive runtime. All findings below were verified against the live
process or the shipped files; nothing here is guesswork.

## 1. Packaging

- `application.xml`: id `com.1212321.bvn.sports`, `<content>launch.swf</content>`,
  `renderMode=gpu`, `maxD3D=9`, `allowMultipleInstances=true`.
- The `.exe` is a packed `CaptiveAppEntry.exe` bootstrap; every PE section is
  high-entropy (~7.98) with no overlay, so `launch.swf` cannot be extracted
  statically — it is encrypted inside the packed `.data`.
- Workaround that worked: dump the AVM2 ABC pools out of the **live process**
  with Frida. The engine ABC (742,924 B, 379 instances, 6695 methods) contains
  all gameplay logic; ~44 sub-ABCs hold fl.controls, textLayout, hurlant crypto
  and the AI eval VM. Decompiling the engine ABC yields the full AS3 source
  (obfuscated control flow, but readable).
- Loose `assets/subswfs/*.swf` are UI only (header frameRate 30, no FPS logic).

## 2. Why the frame rate is capped

`GameConfig` (engine ABC) is already frame-rate independent:

```actionscript
public static var FPS_GAME:int = 60;
public static var SPEED_PLUS:Number = SPEED_PLUS_DEFAULT;
public static function setGameFps(f:int):void { FPS_GAME = f; SPEED_PLUS = SPEED_PLUS_DEFAULT; }
public static function get SPEED_PLUS_DEFAULT():Number { return 30 / FPS_GAME; }
```

Every hold/delay constant in the simulation is `constant * FPS_GAME`
(e.g. `holdFrame = hold * FPS_GAME` in `FighterMcCtrler`, `Bullet`) and every
speed is scaled by `SPEED_PLUS`. One logic tick runs per stage frame, so raising
`FPS_GAME` together with `stage.frameRate` renders more frames per second
without changing simulation time.

Only 30 or 60 is ever assigned, from three places that re-assert continuously:

1. `ConfigVO.applyConfig()` — switch on quality: `low` → `setGameFps(30|60)` +
   `IS_LOW_QUALITY = true`; other tiers → `setGameFps(60)`.
2. `GameInterfaceManager.applyConfig()` — `MainGame.I.setFPS(30|45|60)` by tier.
3. `MainGame.setFPS()` — writes `stage.frameRate`, clamped to 30 when
   `GameConfig.IS_LOW_QUALITY` is true; re-invoked by every `goStage()`
   transition (menus use a literal 30, fight stages use `FPS_GAME`).

Hence the unlock must be re-applied every frame, not set once.

## 3. The IS_LOW_QUALITY trap

`GameRender.render()` (the per-frame pump, registered on stage `ENTER_FRAME` by
`GameRender.initlize()`) invokes each registered logic callback **twice** per
frame when `IS_LOW_QUALITY && config.isExactMoving` — the stock trick for faking
60 fps simulation on a 30 fps stage. At an unlocked rate that double invoke
would run the simulation at 2x speed, so the plugin forces
`IS_LOW_QUALITY = false` on every frame while unlocked.

Ordering matters: the plugin registers its `ENTER_FRAME` listener at priority
1000, i.e. **before** `GameRender.render()` (priority 0), so the flag is cleared
before the double-invoke check runs.

## 4. Injection point: the shipped plugin system

- `GameData` calls `PluginModel.I.initByPath("plugin/")` at startup; every
  `.swf` in `assets/plugin/` is loaded into `ApplicationDomain.currentDomain`.
- `PluginModel.initBySwfIdArray()` resolves the entry class via
  `AssetManager.getSWFEffectClass(const, swfId)` → `getDefinition("PluginMain")`
  (all 10 shipped plugins export exactly one SymbolClass named `PluginMain`),
  instantiates it and reads `.CONFIG = {id, name, author, isRunBack, isNeedDebug}`.
- `CONFIG.isRunBack = true` makes `MenuUtils.createMenuItem` call
  `startBackRun()` during menu init — silent auto-activation. `startBackRun`
  passes `{mainStage, gameRender}` (no `stage`); the windowed path
  `createPluginWindow` passes `{mainStage, stage, gameRender}` and sizes its
  window from a child named `location`.
- `GameRender.addAfter(fn)` / `removeAfter(fn)` are the sanctioned per-frame
  hooks; the plugin instead uses a priority-1000 stage `ENTER_FRAME` listener
  (see §3) and swallows all exceptions so it can never abort the render pump.
- No integrity/anti-cheat check touches plugin files (`ChecksumUtil` is only
  FZip's Adler32).

## 5. Netplay lockstep (why the plugin stands down)

`LockFrameLogic.initServer()/initClient()` (LAN host/client) force
`setGameFps(30)` and gate `GameRender.isRender` on peer agreement each frame;
`dispose()` restores the previous rate. Overriding `FPS_GAME` mid-match changes
`SPEED_PLUS = 30/FPS_GAME`, i.e. the local simulation rate, which desynchronises
both peers. The plugin therefore polls `LANServerCtrl.I.active` /
`LANClientCtrl.I.active` (set true in `gameStart()`, cleared in
`gameEnd()/gameQuit()`) and suspends all overrides while either is true.
Reading `.I` lazily constructs the singleton; its constructor has no side
effects (verified in the decompiled source).

## 6. Verification performed

- Live telemetry channel: the plugin writes
  `%APPDATA%\com.1212321.bvn.sports\Local Store\fps_unlock_status.txt` twice a
  second (plain text; the AIR `File`/`FileStream` APIs are resolved at runtime
  via `getDefinitionByName` so the plugin still compiles against
  `playerglobal.swc`). `tools/readsol.py` asserts
  `engine_fps_game == target`, `stage_framerate == target`,
  `speed_plus == 30/target`.
- Observed on a 120 Hz display at target 120: engine 120, stage 120, measured
  119.8–120.3, speed+ 0.25, IS_LOW_QUALITY false. HUD confirmed on-screen at the
  title menu, which stock forces to 30 fps.
- Hotkeys exercised via `PostMessage`: F3→129, F2→144, F4 OFF→60 (measured
  60.1), F4 ON→restore, F5 preset cycle exact.

## 7. Appendix: character roster (separate project)

While studying the engine we also mapped the data-driven character pipeline:
`config/fighter.x` (encrypted container, decrypted by the embedded loader SWF
`ResUtils.extend` → `net.play5d.utils::AssetLoader`, which bundles hurlant
AES/DES/Blowfish) → `FighterModel.initByXML()`. The live roster (142 fighters,
62 assisters, 29 maps) is dumpable at runtime via the plugin's F6 handler; each
`FighterVO` carries `fileUrl` (e.g. `fighter/act/remilia_scarlet.swf`), face
class keys (`face/*.png` in the preloaded bitmap SWF), BGM and balance fields.
Fighter SWFs must export a `main_mc` class whose timeline carries named hitbox
layers (`FighterHitRange`: `kanmian`, `kj1mian`, `kj2mian`, `zh1..3mian`,
`bsmian`, `kbsmian`, `sbsmian`, `cbsmian`, `assistmian`, ...). The select grid is
`config.select_config.charList.list` rebuilt on every entry to the select
stage, which makes runtime roster injection feasible. The `.x`/`.f` cipher
itself was not recovered — that work is out of scope for this repository.
