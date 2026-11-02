# BVN 帧数解锁（死神vs火影 竞技版）

死神vs火影 竞技版（5DPLAY，Adobe AIR 50.2 内嵌运行时，实测 v3.8.8.6）的帧率解锁插件。

[English](README.en.md)

> 非官方同人工具，与 5DPLAY 无关。本仓库不含任何游戏资源、游戏代码或解密后的
> 游戏数据，仅包含插件源码、构建脚本与逆向分析笔记。

## 功能

- 将帧率从原生 30/60 上限解锁到 20–480 任意值。
- 模拟速度保持正确：引擎本身与帧率无关（`SPEED_PLUS = 30 / FPS_GAME`，所有
  持续/延迟常量均按 `FPS_GAME` 缩放），插件逐帧同步驱动 `GameConfig.FPS_GAME`、
  `stage.frameRate` 与 `MainGame.setFPS()` 三处帧率来源。
- **联机安全**：联机/局域网对战时引擎为 30 帧锁步（`LockFrameLogic`）。插件检测
  到对局后完全自我挂起（HUD 显示 `NETPLAY LOCK`），不破坏同步。
- 通过游戏自带插件系统安装：仅向 `assets/plugin/` 放入一个 `.swf`，不改动其他
  任何文件。

## 安装

1. 从 [Releases](https://github.com/Ser1oux/bvn-fps-unlock/releases)（或本仓库
   `dist/`）获取 `fps_unlock.swf`，复制到 `<游戏目录>\assets\plugin\fps_unlock.swf`。
2. 启动游戏即自动生效（`CONFIG.isRunBack = true`，无需点菜单），左上角出现绿色
   HUD。
3. 若游戏已在运行，需重启一次——插件只在启动时注册。

卸载：删除或改名 `assets\plugin\fps_unlock.swf` 即可。

## 按键

| 按键 | 功能 |
|---|---|
| F1 | 显示/隐藏 HUD |
| F2 / F3 | 目标帧 +15 / −15（按住 Shift 为 ±1） |
| F4 | 解锁开关 / 恢复原生 60 帧 |
| F5 | 循环预设 30/60/90/120/144/165/240 |
| F6 | 导出解密后的角色名册（开发用） |

目标帧、开关状态与 HUD 显隐自动持久化保存（`SharedObject("fps_unlock")`）。

## 验证

游戏运行时执行 `python tools/readsol.py`。它读取插件每秒写入两次的纯文本遥测
（`%APPDATA%\com.1212321.bvn.sports\Local Store\fps_unlock_status.txt`），并校验
`engine == target`、`stage == target`、`speed_plus == 30 / target`。

## 从源码构建

需要 Apache Flex SDK 4.16+（`mxmlc`）与 Java 8+ 运行时；SDK 的
`frameworks/libs/player/32.0/playerglobal.swc` 必须存在（若缺失，可从 Adobe
更新档案下载 `playerglobal32_0.swc`）。

```powershell
$env:FLEX_SDK = "C:\path\to\flex-sdk"     # bin/mxmlc.bat
$env:JAVA_HOME = "C:\path\to\jre"         # 可选，否则需在 PATH 中
.\tools\build.ps1
```

输出：`dist/fps_unlock.swf`。

注意：必须 `<strict>false</strict>`——插件通过运行时解析的 `Class` 类型变量调用
引擎成员（`getDefinitionByName`），严格模式会报错。

## 原理

完整逆向分析见 [docs/REVERSE_ENGINEERING.md](docs/REVERSE_ENGINEERING.md)：三处
原生帧率上限、`IS_LOW_QUALITY` 双 tick 陷阱、插件注入点、联机锁步保护。

## 注意事项

- 本作为竞技版，会上传对战记录；原版 `debugger+.swf` 只认可 30/60 帧，排位/联机
  请按 F4 关闭解锁。
- 显示器刷新率才是真实上限：120 Hz 屏幕上高于 120 的目标不会带来更流畅的画面。
- 逐帧钩子按设计吞掉所有异常：高优先级 `ENTER_FRAME` 监听器中逃逸的错误会中断
  引擎自身的渲染泵。

## 许可

MIT — 见 [LICENSE](LICENSE)。
