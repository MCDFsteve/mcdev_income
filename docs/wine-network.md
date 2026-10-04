# 游戏加载后卡死：IPv6 局域网发现

在 Apple M5、macOS 26.6.2、Wine 11.0_1 上，游戏加载后正常显示约 1–2 秒，随后画面、时间计数和操作一起停止。3.8 OpenGL 和 3.10 渲染龙均复现；切换渲染器、去掉输入和性能补丁、允许本地网络后重启，都没有消除阻塞。

原生线程栈结合 Wine 的 Windows 栈确认主线程停在：

```
RakNet → sendto → WS2_sendto → WaitForSingleObject(INFINITE)
```

两个版本均在向 `ff02::1:19133` 发送 IPv6 局域网发现数据包，`scope_id=0`。系统日志同时出现该目标的 `CFIL: Error: sosend_reinject() failed`。这些证据定位到共同的网络发送路径；没有据此认定 M5 GPU 不兼容。

## 修正范围

macOS 后端在 `MacGameWindow.prepare` 中给 Wine 游戏主进程加载独立的 x86_64 `ipv6-discovery.dylib`。它只处理地址为 `ff02::1`、端口为 `19133`、没有 scope 和控制消息的 `sendmsg`：

1. 优先沿用 socket 的 `IPV6_MULTICAST_IF` 或绑定地址对应的接口。
2. 否则选择当前主网络的可用 IPv6 局域网接口；没有合适的主接口时，使用可用的非回环、非点对点 IPv6 局域网接口。
3. 在地址副本里补充接口编号，调用原 `sendmsg`，保留其返回值和错误。找不到接口时沿用原调用。

调用者的数据、已经指定接口的 IPv6 包、IPv4、单播、其他端口和带控制消息的发送都不修改。没有关闭局域网发现、系统 IPv6、代理、防火墙或隐私保护，也没有修改游戏 EXE、Wine 文件或渲染器。网络组件与输入、游戏顶栏组件组合加载，原有输入开关继续有效。

资源按 SHA-256 校验后写入独立的 `runtimes/network-discovery-v1` 缓存；移动开发目录后仍可复用，损坏的缓存会修复，损坏的应用资源会拒绝启动。Wine 初始化与启动器单独启动的注入器不追加该环境变量。

## 编译与验证

```sh
python3 tools/network/build.py
flutter test test/wine_network_test.dart test/input_guard_test.dart
```

设置 `MCDEV_TEST_WINE_RUNTIME` 指向已解压的 Wine 11.0_1，并用 `MCDEV_CHROME_CLIENT_APP` 指向已构建的 macOS 客户端，可额外验证真实签名应用的启动环境：全屏快捷键开／关时，网络、输入与顶栏组件正确组合；该测试不启动游戏。

需要 Xcode 命令行工具；原生检查验证目标包识别、显式接口优先级、主接口选择、回环/点对点接口回退、正常 UDP 载荷及错误传递。重新编译后核对输出 SHA-256，并更新 `lib/development/wine_network_io.dart` 中的固定值。

M5 本机对照：原始调用可稳定复现卡死，给发现包补充有效接口后 3.8 主菜单持续刷新，设置页可以打开并操作。自动接口选择的正式启动路径也通过 3.9 OpenGL 新世界（同时加载输入组件）和 3.10 渲染龙隔离世界验证：帧/时间计数持续推进，3.10 的背包、暂停菜单、保存退出和正常关窗可用。真实游戏验证应检查世界加载与操作响应；后台进程仍存在不能作为不卡死的判据。此修正不承诺其他网络故障、其他 Wine 版本或持续 60 FPS。
