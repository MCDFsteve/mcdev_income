# Python 热重载（3.10）

在“开发 → 启动游戏”区域、“查看日志”右侧点击 **Python 热重载**，把本次测试已启用行为包中的 `.py` 修改应用到正在运行的世界。第一版只适配官方 x64 **3.10.0.420447**，不更新行为 JSON 或资源包。

## 使用

1. 导入并启用项目，以 3.10.0.420447 启动测试世界。
2. 等待世界脚本加载，按钮变为可用。游戏暂停时先返回游戏。
3. 保存源项目中的 Python 修改，然后点击按钮。成功或失败会显示在提示区，详细堆栈在“查看日志”中。

启动器会自动注入新组件 `python-reload.dll`。不需要自行复制 DLL，也不需要启动 MCS 编辑器。注入、版本校验或辅助包加载失败时，普通游戏仍可运行，热重载按钮显示不可用原因。

## 更新范围

- 更新已加载模块的函数和已有类的方法，保留原函数／类对象，使已注册的绑定回调及 `from module import function` 引用能够继续使用新代码。
- 已有实例继续存在，实例属性保留；构造器、世界初始化和系统注册不会自动重跑。需要新增实例字段时，代码应兼容已有实例，或者重新启动测试。
- 所有修改先由游戏内的 Python 2 解释器编译检查。语法失败时不改动模块或测试副本，修正后可以重试。
- 只同步 `.py` 到装配副本并清理对应 `.pyc`／`.pyo`；保留现有日志捕获初始化包装。源项目、行为 JSON、材质等文件不会被同步操作改写。通过归档导入的项目应修改导入后解压的项目目录。
- 新文件仅同步到已存在的脚本包；尚未导入的模块在后续导入时尝试加载，不会自动注册新系统。
- 删除或重命名文件、更换脚本包、修改包清单、类继承／slots、删除类属性或替换闭包需要重启。其他模块复制保存的常量、容器中的旧值及闭包捕获状态不保证更新。
- 模块顶层代码会重新执行，因此顶层副作用和模块全局变量赋值会再次发生。执行失败可能留下部分更新，无法回滚 Python 对外部世界产生的副作用；按钮会要求重启，不报告成功。应用阶段超时也按结果不确定处理，要求重启。
- 第一版不支持同时重载局域网玩家进程：有玩家正在加入或在线时禁用重载；成功重载后需重启测试再添加局域网玩家。

## DLL 与逆向依据

实现依据实际 3.10 可执行文件及其解包后代码，不依赖 SDK 热更新接口，也不发送编辑器的 `rl` 控制命令。

| 项目 | 校验／位置 |
| --- | --- |
| 游戏 EXE SHA-256 | `9be281dbe08bc591336680d5a50f94d87f3c57ee75b3afcb3cabdf03347e0269` |
| x64 映像大小 | `0x1d28e000` |
| `PyEval_EvalFrameEx` RVA | `0x0f7c0090` |
| `PyRun_StringFlags` RVA | `0x0f7dbc90` |
| `PyErr_PrintEx` RVA | `0x0f7da6e0` |

启动器先校验 EXE 和 DLL 哈希；DLL 再检查架构、映像大小及三个入口的机器码签名，等待解包完成后安装 MinHook。辅助行为包在客户端 tick 中调用专用空函数；DLL 仅拦截这一函数名，在游戏当前 Python 线程及 GIL 上执行调度器。没有 DLL 时空函数不执行重载，也不会生成就绪回执。DLL 初始化工作线程不执行 Python。

逆向探针与实机回归确认，客户端和服务端共享模块表；一次应用会更新双方使用的脚本对象。通信使用每次启动独立的目录、随机 nonce、世界 epoch 和请求 ID，区分语法检查与应用回执；退出或切换世界使旧请求失效。

源码：`tools/python_reload/python_reload.c`、`tools/python_reload/runtime.py`。执行 `python3 tools/python_reload/build.py` 可用 `x86_64-w64-mingw32-gcc` 重建 DLL 并更新 Dart 中的哈希；可通过 `MCDEV_MINGW_CC` 指定编译器。MinHook 沿用仓库已有源码与许可证。

## 验证

```sh
python3 -m unittest discover -s tools/python_reload -p 'test_*.py'
flutter test test/python_reload_test.dart test/python_reload_widget_test.dart test/mod_log_test.dart
```

2026-10-04 在 Apple 芯片 Mac / Wine 上对真实 3.10.0.420447 完成隔离验证：DLL 就绪、语法错误拒绝后修正重试、客户端和服务端旧回调同时执行新代码、已有实例计数器持续递增、未修改源码时跳过操作。日志为 `build/python-reload-live.log`。Windows 共用注入与 Python 代码，尚未对本功能进行 Windows 原生实机验收。

相关 Dart / Flutter 回归为 112 项通过、2 项平台相关跳过，Python 运行时单元测试 7 项通过，修改范围静态检查通过。扩大回归时，`development_page_test.dart` 的首次初始化布局和失败后重试两项用例失败；用原始 `HEAD` 的界面代码重复运行也出现相同失败，记录在 `build/python-reload-baseline-test.log`，不计入本功能通过的回归数量。

显式启用的真实游戏测试：

```sh
MCDEV_LIVE_PYTHON_RELOAD=1 \
MCDEV_LIVE_PYTHON_RELOAD_ROOT="独立的临时开发目录" \
MCDEV_LIVE_PYTHON_RELOAD_SOURCE="已安装游戏和 Wine 的开发目录" \
MCDEV_LIVE_RELEASE_ASSETS="Release 应用的 flutter_assets 目录" \
MCDEV_CHROME_CLIENT_APP="Release 应用路径" \
flutter test test/live_python_reload_smoke.dart
```

测试复用本机已登录账号，在独立目录复制运行环境及游戏，创建专用探针项目；会拒绝使用当前开发目录作为测试写入目标。
