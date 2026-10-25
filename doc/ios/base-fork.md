# koreader-base 的 fork 与 iOS 补丁清单

[ADR-0007](../adr/0007-forked-base-submodule-for-ios.md)、[decisions.md](decisions.md) Q3。`base` 子模块指向 [justinyanme/koreader-base](https://github.com/justinyanme/koreader-base)。它的 master 跟上游 [koreader/koreader-base](https://github.com/koreader/koreader-base) 同步，iOS 补丁合在 master 上，尽量只增不改。构建用法见 [build.md](build.md)。

## 补丁清单

起点是上游 `33b43b5b`。前四个提交从 [hezi/koreader-base-ios](https://github.com/hezi/koreader-base-ios) 的 `6e4bafc0` 移植过来，保留原作者。hezi 的 Lua 改动一律没带：SDL3 安全区和生命周期、夜间模式反色、`runInSubProcess` 内联回退，分别归 B4、B5、B7。

| 提交 | 内容 | 动到的上游文件 |
|---|---|---|
| `ios: add target to the build system` | `TARGET=ios`：`IOS_PLATFORM=iphonesimulator\|iphoneos`、arm64、`IOS_DEPLOYMENT_TARGET`（默认 27.0），用宿主 clang 加 `-target`/`-isysroot` 交叉编译。工具链适配：CMake 的 iOS 工具链、meson 交叉文件、不导出 `MACOSX_DEPLOYMENT_TARGET`。 | `Makefile.defs`、`cmake/CMakeLists.txt` |
| `ios: thirdparty patches for luajit, libk2pdfopt, sdcv` | LuaJIT 只用解释器（iOS 不许 W^X 内存）；k2pdfopt 里不可用的 `system()` 换成 `(0)`；sdcv 不链 AppKit。 | `thirdparty/{luajit,libk2pdfopt,sdcv}/CMakeLists.txt` |
| `ios: enable monolibtic` | iOS 固定 `MONOLIBTIC=1`；Apple 平台不链 `librt`。 | `Makefile.defs`、`thirdparty/cmake_modules/koreader_thirdparty_libs.cmake` |
| `czmq: gate clock_gettime/-lrt detection on NOT APPLE` | czmq 在 Apple 平台不探测 `-lrt`。 | `thirdparty/czmq/cmake_tweaks.patch` |
| `ios: link everything statically into the app executable` | iOS 上不产出任何 dylib：monolibtic 用 `ld -r` 预链接成一个保留全部全局符号的 `libkoreader-monolibtic.o`，SDL3 和 LuaJIT 编成静态库，跳过 macOS 的 `koreader` 启动程序。另外修了 meson 原生工具链把 `ar` 写成 `strip` 的问题（iOS 的 meson 探测会踩到）。 | `Makefile.defs`、`thirdparty/cmake_modules/koreader_targets.cmake`、`thirdparty/sdl3/CMakeLists.txt` |
| B4：SDL 安全区与 viewport 重建 | 转发 `SDL_EVENT_WINDOW_SAFE_AREA_CHANGED`（像素尺寸事件原来已转发）；resize 释放旧 view 的完整 allocation，清除旧 viewport 后由设备层重建；夜间反色变化时更新完整 texture，包括安全区外底色，flash shadow 不消耗最终画面的状态。 | `ffi/SDL3.lua`、`ffi/framebuffer_SDL3.lua` |
| B4：iOS 首帧窗口坐标 | `SDL_SyncWindow` 后仅在 `SDL_GetPlatform() == "iOS"` 时查询 `SDL_GetWindowSize`，把 `win_w/h` 从 display mode 的像素改成实际窗口 point，保证第一帧 dp 标尺和输入缩放成立；桌面、Emulator（包括 Retina 全屏）保持原值。 | `ffi/SDL3.lua` |

B1 构建改动包在 `IOS` 条件里；meson 原生工具链的 `ar` 从 `strip` 改成 `ar` 是所有目标都适用的修正。B4 的首帧 point 查询也只在 iOS 生效；viewport allocation 释放和边缘反色修正适用于 SDL 的 viewport 路径，不改变无 viewport 的桌面渲染，也不改墨水屏 framebuffer。iOS 的 viewport/full buffer 建立后，首个内容帧整帧上传一次，再恢复局部上传；清白帧不提前消费该标记，flash shadow 也不消费。桌面和 Emulator 沿用原有上传范围。

## 每月合并上游

和 l10n（[ADR-0002](../adr/0002-forked-l10n-submodule.md)）一起做：

```sh
cd base
git fetch https://github.com/koreader/koreader-base.git master
git merge FETCH_HEAD          # 在 fork 的 master 上
./kodev build ios             # 回到仓库根，确认 iOS 和其他目标都还能构建
```

合并后把主仓库的 `base` 指针更新到新的 fork 提交。

B1 提 PR 前在 2026-10-25 试过合并当时的上游 master（`77f3c31d`）。上游 `4d779988` 挪动了 `CMAKE_SYSTEM_NAME` 那一行，所以 iOS 工具链块改成放在 `cmake_cross_toolchain` 末尾，用覆盖的方式设置，不改上游那一行。调整后用 `git merge-tree` 验证，无冲突。
