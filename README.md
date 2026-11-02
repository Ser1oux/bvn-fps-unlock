# BVN FPS Unlock / 死神vs火影 帧数解锁

Frame-rate unlock plugin for **死神vs火影 竞技版** (Bleach vs. Naruto, 5DPLAY,
Adobe AIR 50.2 captive runtime, tested on v3.8.8.6).

死神vs火影 竞技版（Adobe AIR 50.2 内嵌运行时，实测 v3.8.8.6）的帧率解锁插件。

> Unofficial fan-made tool. Not affiliated with 5DPLAY. This repository contains
> no game assets, no game code and no decrypted game data — only the plugin
> source, build scripts and reverse-engineering notes.
> 非官方同人工具，与 5DPLAY 无关。本仓库不含任何游戏资源、游戏代码或解密后的
> 游戏数据，仅包含插件源码、构建脚本与逆向分析笔记。

## What it does / 功能

- Raises the game frame rate from the stock 30/60 cap to any value in 20–480.
  将帧率从原生 30/60 上限解锁到 20–480 任意值。
- Simulation speed stays correct: the engine is already frame-rate independent
  (`SPEED_PLUS = 30 / FPS_GAME`, all hold/delay constants scale with `FPS_GAME`),
  so the plugin drives `GameConfig.FPS_GAME`, `stage.frameRate` and
  `MainGame.setFPS()` together, every frame.
  模拟速度保持正确：引擎本身与帧率无关，插件逐帧同步驱动三处帧率来源。
- **Netplay-safe**: during LAN/online matches the engine locks to 30 fps
  lockstep (`LockFrameLogic`). The plugin detects an active match and suspends
  itself completely (HUD shows `NETPLAY LOCK`).
  **联机安全**：联机/局域网对战时引擎为 30 帧锁步，插件检测到对局后完全自我
  挂起（HUD 显示 `NETPLAY LOCK`）。
- Installs through the game's own plugin system — one `.swf` dropped into
  `assets/plugin/`, nothing else modified.
  通过游戏自带插件系统安装：仅向 `assets/plugin/` 放入一个 `.swf`，不改其他文件。

## Install / 安装

1. Copy `dist/fps_unlock.swf` to `<game>\assets\plugin\fps_unlock.swf`.
   将 `dist/fps_unlock.swf` 复制到 `<游戏目录>\assets\plugin\fps_unlock.swf`。
2. Start the game. The plugin activates automatically at menu init
   (`CONFIG.isRunBack = true`); a green HUD appears top-left.
   启动游戏即自动生效（无需点菜单），左上角出现绿色 HUD。
3. If the game was already running, restart it once — plugins register at
   startup only. 若游戏已在运行，需重启一次（插件只在启动时注册）。

To uninstall: delete or rename `assets\plugin\fps_unlock.swf`.
卸载：删除或改名 `assets\plugin\fps_unlock.swf` 即可。

## Controls / 按键

| Key | Action | 功能 |
|---|---|---|
| F1 | toggle HUD | 显示/隐藏 HUD |
| F2 / F3 | target +15 / −15 (Shift: ±1) | 目标帧 ±15（Shift 为 ±1） |
| F4 | toggle unlock / restore stock 60 | 解锁开关 / 恢复原生 60 帧 |
| F5 | cycle presets 30/60/90/120/144/165/240 | 循环预设帧率 |
| F6 | dump live decrypted roster (dev) | 导出解密后的角色名册（开发用） |

Target, unlock state and HUD visibility persist in `SharedObject("fps_unlock")`.
目标帧、开关与 HUD 状态自动持久化保存。

## Verify / 验证

Run `python tools/readsol.py` while the game is running. It reads the plugin's
plain-text telemetry (`%APPDATA%\com.1212321.bvn.sports\Local Store\
fps_unlock_status.txt`, written twice a second) and asserts
`engine == target`, `stage == target` and `speed_plus == 30 / target`.
游戏运行时执行 `python tools/readsol.py`，读取插件每秒两次的遥测文件并校验
引擎/舞台帧率与 speed+ 系数是否与目标一致。

## Building from source / 从源码构建

Requires Apache Flex SDK 4.16+ (`mxmlc`) and a Java 8+ runtime. The SDK's
`frameworks/libs/player/32.0/playerglobal.swc` must exist (download
`playerglobal32_0.swc` from Adobe's updater archive if your SDK lacks it).

```powershell
$env:FLEX_SDK = "C:\path\to\flex-sdk"     # bin/mxmlc.bat
$env:JAVA_HOME = "C:\path\to\jre"         # optional, must be on PATH otherwise
.\tools\build.ps1
```

Output: `dist/fps_unlock.swf`. 输出：`dist/fps_unlock.swf`。

Note: `<strict>false</strict>` is required — the plugin calls engine members
through `Class`-typed variables resolved at runtime (`getDefinitionByName`),
which strict mode rejects.
注意：必须 `<strict>false</strict>`——插件通过运行时解析的 `Class` 变量调用
引擎成员，严格模式会报错。

## How it works / 原理

See [docs/REVERSE_ENGINEERING.md](docs/REVERSE_ENGINEERING.md) for the full
reverse-engineering write-up: the three stock FPS caps, the `IS_LOW_QUALITY`
double-tick trap, the plugin injection point, and the netplay lockstep guard.
完整逆向分析见 [docs/REVERSE_ENGINEERING.md](docs/REVERSE_ENGINEERING.md)。

## Caveats / 注意

- This is the 竞技版 (competitive) build; it uploads match records. The shipped
  `debugger+.swf` only sanctions 30/60 fps, so keep the unlock off (F4) for
  ranked/online play. 竞技版会上传对战记录；原版调试插件只认可 30/60 帧，
  排位/联机请按 F4 关闭解锁。
- Your monitor refresh rate is the real ceiling: on a 120 Hz display, targets
  above 120 render no extra visible frames.
  显示器刷新率才是真实上限：120 Hz 屏幕上高于 120 的目标不会更流畅。
- The per-frame hook swallows all exceptions by design: an escaping error in a
  high-priority `ENTER_FRAME` listener would abort the engine's own render pump.
  逐帧钩子按设计吞掉所有异常，以免中断引擎渲染泵。

## License / 许可

MIT — see [LICENSE](LICENSE).
