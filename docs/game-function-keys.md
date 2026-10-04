# 网易测试游戏的 F1–F12 默认功能

2026-10-03 核对本机的 `3.10.0.420447`、`3.8.0.313229` x64 客户端。这里记录的是默认键位和代码中的动作；调试环境、当前界面、录像状态及自定义键位会影响是否执行。macOS 左上角“功能键”菜单使用这些名称，并继续发送原来的物理 F 键。

| 按键 | 菜单功能 | 核对结果 |
| --- | --- | --- |
| F1 | 显示 / 隐藏界面 | `button.hide_gui`，键码 `0x70`。 |
| F2 | 截图 | `key.screenshot` 默认值 `113`（`VK_F2`），输入映射 `button.screenshot`。 |
| F3 | 调试信息下一页 | `button.render_debug`，键码 `0x72`；游戏内提示原文为 `[F3]: next, [F4]: prev`。 |
| F4 | 调试信息上一页 | `button.render_debug_reverse`，键码 `0x73`。 |
| F5 | 切换视角 | `key.togglePerspective` 默认值 `116`（`VK_F5`），输入映射 `button.toggle_perspective`。 |
| F6 | 穿墙飞行（调试） | `button.no_clip`，键码 `0x75`。公共调试映射还声明了 `button.frame_timer_display`，但本轮未确认其实际消费路径，未将帧耗时显示写进菜单。 |
| F7 | 未发现默认单键功能 | 在核对的普通键位表中未发现单键动作。复合输入配置出现了 `0x76`，不能据此认定单独按 F7 有功能；模组仍可处理该键。 |
| F8 | 显示 / 隐藏纸娃娃 | `button.hide_paperdoll`，键码 `0x77`；HUD 处理为 `button.hide_paperdoll_hud`。 |
| F9 | 模拟挂起 / 恢复（调试） | `button.suspend_resume`，键码 `0x78`，回调交给 AppPlatform 的调试路径。不同平台实现可能不执行此动作。 |
| F10 | 录像 / 显示隐藏提示 | `key.record` 默认值 `121`（`VK_F10`），对应 `button.record`；同时存在 `button.hide_tooltips` 的固定 `0x79` 绑定。由当前输入上下文决定处理路径。 |
| F11 | 渲染帧捕获（需 RenderDoc） | 3.10 的 BGFX 渲染调试信息明确显示 `[F11 - RenderDoc capture]`，依赖 RenderDoc 捕获环境。3.8 未发现相应默认单键动作，菜单明确标注；其他版本使用“默认功能待核对”。原生 macOS 全屏仍由“窗口 → 切换全屏”提供。 |
| F12 | 播放回放 | `key.replay` 默认值 `123`（`VK_F12`），对应 `button.replay`。另有固定 `button.f12_touch` → `onF12Touch` 事件，但未确认脚本中的实际效果，未据函数名将它解释为切换触控模式。 |

F3/F4 是此客户端的多页调试信息；页面名称包括 Basic、ImGui、Worker Threads、Render Chunks、Profiler、Image Memory、Audio、Client Network 等。它们不是 Java 版 F3 屏幕的菜单说明。

## 二进制和地址依据

原始文件位于开发目录的 `games/<版本>/Minecraft.Windows.exe`，SHA-256：

- 3.10：`9be281dbe08bc591336680d5a50f94d87f3c57ee75b3afcb3cabdf03347e0269`
- 3.8：`01a64912e20bbe7568be446461262a4bb892f671a2a5e15d550db2017902e7aa`

游戏 EXE 包含压缩代码。本轮复用本机已有的解包后运行时节转储，以 Capstone 反汇编 x64 代码并跟踪 RIP 相对引用；映像基址为 `0x140000000`。3.10 转储位于 `/Library/Afolder/WineProject/MCS/analysis/renderer/runtime-3.10`，3.8 转储位于 `/Library/Afolder/WineProject/MCS/analysis/performance/runtime-3.8`。下表地址均是相应转储的虚拟地址，不是原始 EXE 文件偏移。

| 证据 | 3.10 地址 | 3.8 地址 |
| --- | --- | --- |
| F1 `0x70` → `button.hide_gui` | `0x1447628cf`、`0x1447628e2` | `0x143a2b8ca`、`0x143a2b943` 附近 |
| F3 `0x72` → `button.render_debug` | `0x1447590a5`、`0x14475912f` | `0x143a2250b`、`0x143a22582` 附近 |
| F4 `0x73` → `button.render_debug_reverse` | `0x144759145`、`0x144759158` | `0x143a22598`、`0x143a225be` |
| 调试页面提示字符串及引用 | `0x1530725f8`、`0x14730b976` | `0x1507f70e0`、`0x1474474b1` |
| F6 `0x75` → `button.no_clip` | `0x144762a9a`、`0x144762aad` | `0x143a2bcea`、`0x143a2bd10` |
| F8 `0x77` → `button.hide_paperdoll` | `0x14476290c`、`0x14476291f` | `0x143a2b959`、`0x143a2b983` |
| F9 `0x78` → `button.suspend_resume` | `0x144759182`、`0x144759195` | `0x143a2264b`、`0x143a22671` |
| F10 `0x79` → `button.hide_tooltips` | `0x144762949`、`0x14476295c` | `0x143a2ba12`、`0x143a2ba3c` |
| 录像 / 回放动作注册 | `0x14782746b`、`0x1478274c3` | `0x147864d25`、`0x147864d7b` |
| `key.record` / `key.replay` 字符串 | `0x153132be8`、`0x153132bf8` | `0x15084f190`、`0x15084f1a0` |
| F11 RenderDoc 提示及引用 | `0x1546d14d8`、`0x14e7445b1` | 未发现 |
| F12 `0x7b` → `button.f12_touch` | `0x1447601df`、`0x1447601f2` | `0x143a29685`、`0x143a29668` |

3.10 的 F9 回调链为注册点 `0x147827413` → 回调表 `0x1531391c0` → `0x14780bd70` → `0x1470b1ff0` → AppPlatform。F12 触控事件的处理在 `0x1470add50`，`0x1470add6f` 读取 `onF12Touch`；这仅证实事件名，不足以命名具体界面功能。3.10 还存在默认关闭的 `load_renderdocdll` 选项，定义位于 `0x148616ec5`–`0x148616f10`。

两份隔离游戏生成的 `minecraftpe/options.txt` 均记录 F2/F5/F10/F12 为 `113/116/121/123`；对应游戏自带的简体中文资源将 `key.record`、`key.replay` 翻译为“录像”“播放”。核对配置时只读取这四项键位，不读取登录数据。

## 验证范围

`test/window_chrome_test.dart` 的 5 项测试通过，验证功能名称、版本差异、F1–F12 物理参数及原生菜单序列化。`tools/windowing/test.py` 通过，验证菜单 target 与原生键盘投递；相关 Dart 静态检查无问题。

macOS Release 构建、独立应用副本的深层签名校验通过，并确认构建后的 App.framework 包含全部 12 项新名称。另使用 `tools/windowing/native/probe.m` 的独立 Cocoa 窗口加载实际 Release 框架和窗口组件，读取原生 `NSApp.mainMenu`，确认 3.10 的 12 项功能菜单名称均已注册。该验证不需要登录、存档或启动游戏。静态绑定和菜单验证不等于已逐项观察到游戏效果，尤其 F6/F9/F11 的调试条件没有在本轮实机验收。
