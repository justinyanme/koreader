# 构建与运行

B1（#89）的构建骨架。决策依据：[decisions.md](decisions.md) Q27、Q31、Q35、Q40–Q42；base 的 fork 与补丁清单见 [base-fork.md](base-fork.md)，发布通道见 [delivery.md](delivery.md)。

## 命令

| 命令 | 作用 |
|---|---|
| `./kodev build ios` | 模拟器 Release 包（arm64 `iphonesimulator`），产物在 `koreader-ios-arm64-apple-ios27.0-simulator/DerivedData/Build/Products/Release-iphonesimulator/JustReader.app`。 |
| `./kodev build ios-device` | 真机 Release 包（arm64 `iphoneos`）：运行 fastlane 的 `build_release` lane，也就是 `ios:tf` 去掉上传的部分。在专用钥匙串里用 Team `V88UWDRASU` 的 App Store profile 签名，导出 `platform/ios/Build/JustReader.ipa`，归档留在 `koreader-ios-arm64-apple-ios27.0/JustReader.xcarchive`，然后对归档里的 App 跑门禁。需要 [delivery.md](delivery.md#前提) 的 `.env` 和 bundler 环境。 |
| `./kodev run ios [参数]` | 把模拟器包装进已启动的模拟器（或 `IOS_SIMULATOR` 指定的名字/UDID）并启动，控制台输出接到终端。参数原样交给 `reader.lua`；相对路径按 App 的数据容器解析，比如 `./kodev run ios Documents/book.epub`。 |

一次构建依次做三件事：

1. Xcode 的预构建脚本（`platform/ios/scripts/xcode-prepare.sh`）运行 `make TARGET=ios xcode-prepare`，内容包括：
   - 构建当前 SDK 的 koreader-base；
   - 按 `make/ios.mk` 的排除清单把 Lua 树同步成 payload；
   - 生成 `link.args` 和导出清单。
2. `tuist generate`，再用 `xcodebuild` 编译 Swift 启动器并静态链接。
3. 后处理脚本把 payload 拷进 `JustReader.app/koreader/`，然后跑符号门禁。

Xcode 和 fastlane 走的是同一个工程、同一个预构建脚本，所以从 Xcode 直接构建、跑 `ios:tf` 或 `ios:ota`，得到的都和 kodev 一样。

## 前提

- Xcode 27.1，以及 iOS 27.0 模拟器运行时。
- [delivery.md](delivery.md) 的工具链：`mise trust`、`mise install`。
- KOReader 的 macOS 构建依赖：`brew install autoconf automake bash binutils cmake coreutils findutils gettext gnu-getopt libtool make meson nasm ninja pkgconf util-linux`。
  - kodev 需要 GNU 版的工具排在 `PATH` 前面：`export PATH="$(brew --prefix)/opt/findutils/libexec/gnubin:$(brew --prefix)/opt/gnu-getopt/bin:$(brew --prefix)/opt/make/libexec/gnubin:$(brew --prefix)/opt/util-linux/bin:$PATH"`。
  - Xcode 里的脚本相位自己会设置这些路径。

## 静态链接

App 里没有任何独立的 `.dylib`（Q1）：

- **koreader-base**：在 iOS 上 base 的 monolibtic 产物是一个可重定位目标 `base/build/<triple>/libs/libkoreader-monolibtic.o`，它用 `ld -r` 把 base 的全部模块和第三方静态库预链接在一起。
- **LuaJIT 和 SDL3**：都编成静态库。
- **App 链接**：把这三者整个装进可执行文件。`platform/ios/ffi-symbols.txt` 的每一行成为一个导出符号，Release 的死代码裁剪只保留 App 用到的代码和这些导出。归档时 `STRIP_STYLE=non-global`，保证导出符号不被 strip。
- **Lua 侧**：启动器先跑 `platform/ios/ios-shim.lua`，再跑 `reader.lua`。按名字加载的库（`ffi.load`）都直接返回 `ffi.C`；`libs/` 下的 Lua C 模块从可执行文件本身解析。这个文件不改 base。

## 符号门禁

`platform/ios/scripts/check-symbols.sh APP SYMBOLS SOURCES` 在两个地方运行：Xcode 后处理一次，`./kodev build` 结束时对最终产物（真机是归档里 strip 过的可执行文件）再跑一次。下面任一条不满足，构建就失败（Q27、Q35）：

- **符号齐全**：`nm -gU` 必须能看到 `ffi-symbols.txt` 里的每个符号，以及 Swift 源码里每个 `@c(ko_ios_*)` 桥。B1 没有桥，桥清单为空，门禁照常通过。
- **没有动态库**：App 里不许有 `.dylib` 或 `.so`。

门禁不检查系统库符号，它们由 dyld 解析。按能力未启用路径的 cdef 也不列进清单。

**反例**：`IOS_GATE_DROP=sqlite3_close ./kodev build ios` 会把这个符号从导出里拿掉，App 重新链接后门禁报 `does not export: sqlite3_close`，构建失败。之后不带变量再构建一次即可恢复。

**清单维护**：清单随 iOS 模块集手工维护，不自动扫全部 cdef。启用新的 Lua FFI 调用时，把用到的静态库符号补进去。

## 随包插件（Q31）

以 Android 的排除清单为起点（SSH、autofrontlight、hello、timesync、tools），另外排除两类：

- **执行外部程序或 shell 的**：terminal、systemstat、keepalive、httpinspector。
- **墨水屏专属、或由 iOS 系统接管的**：autowarmth、autostandby、autosuspend、autodim、coverimage。

统计、KOSync、Calibre 无线、云存储、OPDS、封面浏览、自动翻页、生词本都保留。词典不是插件，在 frontend 里。

## 数据位置

`KO_HOME` 暂时是 `Library/Application Support/koreader`，B3（#91）会改成 Q10 的布局。
