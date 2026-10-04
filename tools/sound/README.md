# 游戏无声输出

启动区的“关闭声音”默认不勾选，按测试页保存；主菜单、测试世界和该测试页启动的局域网玩家都继承此选项。当前适配 Windows 与 macOS Wine 的 **3.10.0.420447 x64**。

从实际游戏的导入表及 `fmod64.dll` 导出/反汇编确认音频调用，没有使用 ModSDK。启动器校验游戏 EXE、FMOD DLL、注入 DLL 与注入器的完整 SHA-256，再通过现有路径/PID 校验的注入器加载 `sound-patch.dll`。

DLL 拦截 FMOD 的 System `init`、`update`、`setOutput`、`setOutputByPlugin`、`playSound`、`playDSP`，将输出固定为 NOSOUND（2）。该后端保留实时混音时钟，不打开声音播放设备；已初始化系统在下一次 update/play 时切换，新系统从初始化时使用无声输出，游戏重新选择硬件输出也会被拦截。只修改注入进程内的 FMOD 调用。

注入就绪前通过临时 `audio_main:0` 防止启动声音。退出后恢复原主音量并保留游戏写入的其他设置；旁路备份支持启动器意外退出后下次启动恢复。只有原生日志确认 `ready` 且 `output=2` 才算就绪，持续监测失败；校验、注入或初始化失败会报错，运行时失败会停止本次测试。

构建：`python3 tools/sound/build.py`。需要 `x86_64-w64-mingw32-gcc`，使用仓库内 MinHook（其许可证见 `tools/performance/minhook/LICENSE.txt`），构建结果自动更新 Dart 哈希。

原生集成探针：编译 `tools/sound/probe.c`，在隔离 Wine prefix 或 Windows 中运行 `probe.exe <fmod64.dll> <sound-patch.dll> <early|late>`，并设置 `MCDEV_SOUND_LOG` 为可写的 Windows 路径。它覆盖初始化前/后的加载、恢复硬件输出的请求、第二个音频系统及正常 update/release。

完整启动验证：显式设置 `MCDEV_LIVE_SOUND=1`、`MCDEV_LIVE_SOUND_ROOT`（隔离目录）、`MCDEV_LIVE_SOUND_SOURCE`（已安装的开发目录）、`MCDEV_LIVE_RELEASE_ASSETS`、`MCDEV_CHROME_CLIENT_APP`，运行 `flutter test test/live_sound_smoke.dart`。此验证使用真实已登录账户，但仅操作隔离副本及其测试存档。

验证记录（2026-10-04）：实际 FMOD 的 early/late 两种探针均通过，原硬件输出为 8，注入后及请求恢复硬件输出后均为 2，第二个音频系统同样为 2。macOS/Wine 的隔离 3.10 世界成功加载，原生日志累计 2101 次无声更新、0 次失败；退出恢复 `audio_main:1`，取消勾选后的主菜单启动没有静音 DLL 日志。101 项相关单元、界面与回归测试通过（另有 2 项平台跳过），静态检查无问题，macOS Release 构建成功。Windows 注入路径已接入现有 PID 注入器，本次没有 Windows 实机环境。
