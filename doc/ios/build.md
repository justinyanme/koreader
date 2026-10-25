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
- **Lua 侧**：启动器把 13 个链进可执行文件的 Lua C 模块（`luaopen_*`）注册到 `package.preload`，然后先跑 `platform/ios/ios-shim.lua`，再跑 `reader.lua`。shim 只让 bundled 库（`libs/` 路径和 `lib*.dylib` 形式的名字）和 `pthread`（KOPT 后台重排用，iOS 上只在 libSystem 里）的 `ffi.load` 返回 `ffi.C`，其他名字照常交给 `ffi.load`，找不到库时报错清楚；`libs/` 下的 Lua C 模块改从可执行文件解析，只作兜底。base 不改。

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

Q10 的布局（B3，#91），实现在 `frontend/device/sdl/iosstorage.lua`：

- **书**：`Documents`，即主目录，Files 里显示为"我的 iPhone/Just Reader"，Finder 文件共享也是它（`UIFileSharingEnabled`）。"文件"页以它为唯一的根。
- **设置、笔记、docsettings**：`KO_HOME` = `Library/Application Support/koreader`。`.sdr` 集中放在 `docsettings/`（`document_metadata_folder = "dir"`），所以 Files 里看不到。
- **可重建缓存**：`KO_CACHE_HOME` = `Library/Caches/koreader`。`KO_HOME/cache` 是指向它的软链，系统清掉 Caches 后下次启动重建。
- **导入**：三条路都是系统给的副本（`Documents/Inbox`、`tmp/<bundle id>-Inbox`），由 `frontend/apps/shelf/bookimport.lua` 移进主目录，重名不覆盖。
- **容器路径变化**：重装或更新后数据容器的路径可能变，下次启动把 docsettings、设置、历史、`settings/*.lua` 和封面缓存里的绝对路径搬到新路径。
- **备份**：不做任何备份排除（Q33）。
