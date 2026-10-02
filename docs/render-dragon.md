# 渲染龙与灵动视效：macOS Metal 适配

本次沿用用户已确认恢复的 `82792a5`（60帧）代码，新增独立的渲染龙路径。当前精确支持网易 `3.10.0.420447` Haldra x64，要求 Apple 芯片 Mac、macOS 14 或以上及 Rosetta 2。游戏 EXE 保持官方下载内容；未给其他版本注入这些地址。

## 使用

1. 在“开发”中安装 Wine，浏览完整版本清单并安装 `3.10.0.420447` Haldra x64。
2. 选择该版本，打开“测试设置”，选择“渲染龙”。
3. 勾选“灵动视效（实验性）”，点击“完成”后启动测试世界。首次启动下载约 18 MB 的 DXMT 组件；已有下载会校验并复用。
4. 保留“限制 60 帧”使用游戏的 60 帧上限，或关闭它取消启动器限帧。灵动视效的性能取决于场景与画质；本次未完成前台帧率验收。

灵动视效按版本保存，默认关闭。运行期间禁止修改设置，重启游戏后生效。“仅打开游戏主菜单”沿用原默认渲染流程；灵动视效开关用于测试世界。其他尚未适配版本显示禁用说明。

## 实现

路径为 **RenderDragon → 官方 D3D11/SM5 材质 → DXMT 0.80 → Apple Metal**。

官方 3.10 材质包含 SM5 字节码，可以由 D3D11 使用。此版本的 deferred 后端白名单没有包含 D3D11；适配 DLL 请求游戏已经实现的 D3D11 后端，并在真实 feature level 至少 11.0、原 Metal 分支检查的格式能力位有效时允许 deferred。没有伪造设备能力、替换官方材质或取消 BGFX 的校验。

DXMT 0.80 使用旧版 Wine macdrv 的窗口结构。Wine 11 在相同偏移处已改为矩形，直接导出内部窗口结构会产生无效指针。新的 `winemac.so` 提供精确的旧 ABI 包装：每个 Metal view 使用独立 client surface，参与 Wine 的尺寸更新、分离和销毁流程，保留 surface 引用并按正常生命周期释放。同时保留当前已验证的 Wine OpenGL 上下文兼容处理。

DXMT 会给当前绑定的着色器保留公开 COM 引用，而 BGFX 调试构建在销毁 shader 时要求最后一次 `Release` 返回 0。适配只在销毁该 shader 前解除匹配的 VS/PS/GS/HS/DS/CS 绑定，然后调用完整的原销毁函数。GetShader 的临时引用照常释放，所有原断言保持有效；不伪造引用计数，也不额外重复 Release。这消除了正常关窗时的 `RefCount is 1 (expected 0)` 断言。

3.10 的 D3D11 结构化缓冲区创建路径收到 `flags=0`，因此只创建动态 SRV；官方亮度直方图、双边网格等计算着色器却需要 UAV。Metal GPU 校验抓到直方图清零 shader 写入共享顶点缓冲的 offset 336，导致全屏四边形首顶点被清零，出现条带和细长三角形。初次 CPU 上传与 GPU 回读本来正确，因此此前“上传时修正纹理坐标”的假设已被推翻，旧修正已移除。

适配在该版本的 D3D11 `createStructuredBuffer` 入口补上 `COMPUTE_WRITE`（0x200），由原创建代码生成 DEFAULT 缓冲区及正确的 SRV/UAV，保留长度和结构步长。结构化数据上传改用 `UpdateSubresource` 字节区间复制，避免对 DEFAULT 资源执行原 `WRITE_DISCARD`，短更新保留尾部数据。销毁仍走原生命周期，不修改官方材质、计算 shader、顶点数据或 draw 绑定；正式路径不做 GPU 回读。新增入口同样经过函数签名校验。

独立的 `renderer-inject.exe` 核对唯一游戏进程、完整路径以及解码后的可执行入口签名。启动器先校验完整 EXE SHA-256，再应用 DLL。原 3.8 注入器只识别其自己的布局，继续用于原有性能补丁。

## 文件与回退

| 位置（相对开发数据目录） | 用途 |
| --- | --- |
| `runtimes/wine-11.0_1-mcs-v1/` | 原已验证的 OpenGL Wine，不覆盖 |
| `runtimes/wine-11.0_1-dxmt-0.80-v1/` | 按需建立的独立 Metal Wine |
| `runtimes/renderer-patch-v1/` | 渲染 DLL 与专用注入器 |
| `downloads/dxmt-v0.80-builtin.tar.gz` | 固定哈希的 DXMT 下载缓存 |
| `logs/renderer-<时间戳>.log` | 补丁状态、真实后端和能力、shader 清理记录 |

独立 Wine 逻辑大小约 666 MB。在 APFS 上优先克隆，未修改的数据块可共享；其他文件系统会复制。实际磁盘占用依赖文件系统，18 MB 是组件压缩下载量。

启动时临时设置 `graphics_mode:2`（开启灵动视效）或 `1`（普通渲染龙）和 `gfx_msaa:1`。退出或启动失败后只恢复这两项原值，保留游戏写出的其他画质与未知设置。共享 prefix 需要安装经过校验的 `winemetal.dll`；原游戏文件、3.8 图形补丁和模组源文件不修改。切回 3.8 OpenGL 会使用原 Wine 与原性能 DLL。

游戏下载、组件下载和 runtime 路径仍跟随用户设置的开发数据目录。渲染日志可从现有日志弹窗查看、筛选、复制和导出；状态日志不含账号令牌。

## 验证与边界

2026-10-01，在 Apple M4 的隔离游戏与存档副本中完成了 DXMT 路径验证：

- 真实 BGFX 后端为 D3D11（枚举 2），设备 feature level 为 11.1；`graphics_mode:2` 没有回退。
- 游戏成功创建官方 `VolumeScattering`、`DeferredMixedResolution`、`DeferredWater`、`DeferredIndirectSpecular`、`Bloom`、`LocalExposure`、`ColorPostProcessing` 等材质。
- 被动 GPU 调用诊断的一次世界运行记录了 590,464 次 draw、36,296 次 dispatch、12,838 次成功 Present，没有其他 Present 结果。这是后端运行证据，不是前台帧率测量。
- 修复着色器释放后，隔离世界运行及请求关窗没有 BGFX 引用计数断言；关窗完成了 Level、客户端、服务端和渲染器的销毁。
- 使用 Release 包内正式组件完成两次生产启动器测试：灵动视效开启、关闭各运行超过 60 秒，真实后端与能力均符合预期；均完成请求关窗，没有渲染断言，临时选项恢复正确，关闭后可以重新启动。
- macOS Release 构建成功，Flutter 报告约 **56.2 MB**；核对了正式包内 DLL、注入器、macdrv 与源码/许可证资产。
- 常规自动测试 **162 项通过**。本轮新增覆盖按版本保存、运行中拒绝修改、不支持版本禁用、EXE 与组件损坏拒绝、缓存修复、渲染设置恢复以及 1024×600 的设置交互。本轮相关 Dart 文件静态分析无问题。

### 2026-10-02 结构化缓冲区修复

在隔离游戏和存档副本中，从正式启动流程冷启动并注入诊断适配，获得以下证据：

- 未修复时，直方图清零/统计与双边网格计算的 UAV 槽位全部为空；结构化资源描述为动态 SRV，没有 UAV。
- 修复后，直方图 u3 是 1024 字节、步长 4 的结构化 UAV；双边网格 u4 是 12800 字节、步长 8 的结构化 UAV。使用官方计算着色器与原 dispatch 数量。
- 开启 Metal GPU validation 后，原非法 store/load 消失；共享 quad 首顶点多次 GPU 回读保持 `(0,0,0,1; 0,1,0)`，没有再次清零。
- CUA 直接检查夜晚和正午世界，地形、树木、天空及实体正常，原大片黑色/彩色条带与拉伸消失。截图与结构化诊断保存在 `MCS/analysis/renderer/compute-probe/`。
- 隔离测试运行约 9 分钟，正常请求退出，无 BGFX 断言，临时渲染选项恢复。
- Metal validation 仍报告部分官方顶点着色器的 NaN/Inf 插值诊断，不能宣称所有 GPU 校验项清零。

正式 Release 回归（不注入额外诊断 DLL，不启用 Metal validation）：

- 新版包内 DLL 哈希与源码声明一致，重新构建 macOS Release 成功（56.2 MB）。渲染补丁与窗口包装相关测试 5 项通过，另 1 项显式启用的 Wine 环境测试跳过；本轮相关 Dart 静态分析通过。
- 灵动视效开启，冷启动进入带原模组副本的世界；夜晚、正午、换方向地形和近处水面均可直接观察，没有原条带/拉伸。正常退出与临时设置恢复通过。
- 关闭灵动视效后重新打开同一副本，普通渲染龙画面正常，先前保存的海岸位置 `(135,66,87)` 和物品栏保留。
- 原 3.8 图形 DLL、注入器 SHA-256 与已恢复的 60 帧基线相同，四个性能相关 Dart 文件没有差异。
- 本轮机器可读结果及截图：`MCS/analysis/renderer/compute-probe/release-vibrant-result.json`、`release-forward-result.json`、`release-fixed-water.png`、`release-forward-reopened.png`。

早期 `tools/renderer/tests/fullscreen_uv.py` 只证明人为损坏的 quad 会造成错误采样，不是本次根因修复的验收测试。

游戏窗口共享已修复：游戏进程从 runtime 内正规 `我的世界测试.app` 执行真实 Wine loader。CUA 可直接读取和操作游戏窗口，见 [游戏窗口读取](development.md#游戏窗口读取)。本次修复针对画面正确性；尚未完成灵动视效稳定 60 帧验收。

正式启动器 Release 资产的灵动视效开启/关闭、关闭后重启与临时设置恢复验证记录位于本机的 `MCS/analysis/renderer/`，结果以 `renderer-*-vibrant.json`、`renderer-*-forward.json` 为准。

## 校验值

| 文件 | SHA-256 |
| --- | --- |
| 3.10.0.420447 游戏 EXE | `9be281dbe08bc591336680d5a50f94d87f3c57ee75b3afcb3cabdf03347e0269` |
| DXMT v0.80 builtin 压缩包 | `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d` |
| renderer-patch.dll | `71fa0db14a6d1a93d4664c6e81e8c304c13ebfba01121a38119e6ac0a5bef9ae` |
| renderer-inject.exe | `8a8fbedd6b058e02c0994c10a957c8185ace161181c6740f0989268f70153f8f` |
| winemac-dxmt.so（临时签名后） | `cb1649390b73064804a87761eee743fe142d6056dc9678eb4c1ee804803ed6bd` |

每个 DXMT 解压组件另有独立校验值，见 `lib/development/render_dragon.dart`。只从固定哈希归档提取白名单中的四个文件，暂存验证完成后才安装。下载依次使用官方 GitHub、gh-proxy.com、ghfast.top；代理不是大学镜像。

## 来源、许可证与构建

- [DXMT 0.80 官方发行](https://github.com/3Shain/dxmt/releases/tag/v0.80)，MIT，使用原发行二进制，未修改 DXMT。
- [Wine 11.0 官方源码](https://codeload.github.com/wine-mirror/wine/tar.gz/refs/tags/wine-11.0)，归档 SHA-256：`f09e8153aa46a581d2b56a5b1363b04832070b9409d9244a68cf482b243ff14a`。Wine 与新增桥接源码为 LGPL-2.1-or-later。
- DLL 使用 [MinHook](https://github.com/TsudaKageyu/minhook)，BSD。渲染适配 DLL、注入器和其构建脚本为 MIT。

许可证全文在 `tools/renderer/licenses/`。对应 Wine 修改的完整 patch、桥接源码及构建脚本在 `tools/renderer/wine/`；这些资料与 native 源码、MinHook 构建所需源码也随 Flutter 资产打包。Wine 完整未修改部分由上面的固定 tag 归档提供。

构建本轮 DLL 和注入器（不重新生成原 3.8 DLL）：

```sh
MCDEV_MINGW_CC=/opt/homebrew/bin/x86_64-w64-mingw32-gcc python3 tools/renderer/build.py
```

脚本使用固定 PE timestamp、去除调试符号和静态 libgcc。在本机连续构建所得校验值一致；更换工具链后需更新源码中的校验值并重做测试。

构建 macdrv：先核对并解开官方 Wine 11.0 归档，准备 Xcode CLI tools 与 GNU Bison 3.8+（系统 Bison 2.3 不够），从全新的源码树执行：

```sh
# Bison 可放在独立工具目录，无须升级 Xcode。
PATH=/absolute/path/to/bison-3.8.2/bin:$PATH \
  tools/renderer/wine/build.sh /absolute/wine-wine-11.0 /absolute/wine11-build
```

脚本仅构建 x86_64 的 `dlls/winemac.drv/winemac.so`，设置 `MACOSX_DEPLOYMENT_TARGET=14.0` 并临时签名。核对导出的 `_macdrv_functions`、最低系统版本、修改内容和哈希后才替换 `assets/development/winemac-dxmt.so`。编译器、SDK 和签名变化可能改变哈希。

隔离生产启动验收使用 `test/live_renderer_smoke.dart`，必须明确提供副本目录、版本与资产目录。测试会复用已有 Flutter 登录，启动隔离世界，检查后端、能力、选项与存活状态，请求关闭并检查断言和设置恢复。不会修改用户原模组勾选或原存档。

```sh
MCDEV_LIVE_PERFORMANCE_ROOT=/absolute/isolated/development \
MCDEV_LIVE_GAME_VERSION=3.10.0.420447 \
MCDEV_LIVE_RENDERER=dragon MCDEV_LIVE_VIBRANT=1 \
MCDEV_LIVE_RELEASE_ASSETS=/absolute/app/Contents/Frameworks/App.framework/Resources/flutter_assets \
flutter test test/live_renderer_smoke.dart --no-pub --reporter expanded
# MCDEV_LIVE_VIBRANT=0 验证普通渲染龙；重复运行验证关闭后可重新启动。
```
