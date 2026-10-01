# Native performance patch

Build with `python3 tools/performance/build.py` using the installed
`x86_64-w64-mingw32-gcc`, or set `MCDEV_MINGW_CC` to that compiler's path.
Only the two generated assets are packaged. Game files and Wine are downloaded
independently. Update `lib/development/performance_patch.dart` when asset hashes
change; tests verify exact PE hashes and architecture.

The opt-in machine diagnostic `test/live_performance_smoke.dart` runs the real
launcher with the existing Flutter login and the assets from a Release bundle.
Prepare an independent copy of the development data (runtime, game, prefix and
projects manifest), then set `MCDEV_LIVE_PERFORMANCE_ROOT` to that root and
`MCDEV_LIVE_RELEASE_ASSETS` to the bundle's `flutter_assets` directory before
running `flutter test test/live_performance_smoke.dart`. The script refuses the
real development root, keeps launcher preferences in memory, and closes only
its test prefix. Optional `MCDEV_LIVE_WARMUP_WINDOWS=10` excludes 1,200 warm-up
frames; `MCDEV_LIVE_MIN_FPS=58` enforces the local performance acceptance gate.
Use one active rendering game when assessing FPS. Desktop interaction and
visual correctness remain separate checks.

The native code is restricted to the benchmarked game and Wine 11 layouts.
Read the evidence, failure behavior, CPU cost and outstanding validation in
[`docs/game-performance.md`](../../docs/game-performance.md).

MinHook sources are from v1.3.4 at
`c3fcafdc10146beb5919319d0683e44e3c30d537`; see `minhook/LICENSE.txt`.
