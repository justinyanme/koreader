# iOS 阶段 A 技术验证报告

日期：2026-10-25。对应 [#86](https://github.com/justinyanme/koreader/issues/86)，依据 [可行性报告第 2、4 节](../iOS-feasibility.md)、[决策记录](decisions.md) Q23/Q35/Q36/Q42/Q46–Q48 与 [ADR-0010](../adr/0010-ios-native-layer-swift-uikit-tuist.md)。后轮决策覆盖前轮；持久化按 Q48 判定 ADR-0009 的设计原型。

**结论：go。按 Q23/Q42/Q48 的模拟器临时门禁，两台 Release 独立启动、清醒阅读满 30 分钟、三项性能、启用路径 FFI 解析及 B5 设计原型持久化均通过；最小 Swift 静态桥可行。没有剩余 T0 阻塞项，可继续 B1；完整静态链接、正式生命周期/原子保存和真机复核仍须各后续票完成。**

本票只交付本报告和 [手工验收清单](acceptance.md)。实验代码、工程、构建产物、样书与原始证据均在 `/Volumes/T5/github/ios-phase-a/`，不进入本仓库。本仓库没有修改生产 Lua、base 指针、GitHub Actions 或父 issue #85；下述 B5 原型只修改仓库外副本。

## 环境与版本

| 项目 | 实际值 |
| --- | --- |
| 顶层 | [hezi/koreader-ios@a7cf2a98a28c6e70fb33087549bfb4a734ed19bc](https://github.com/hezi/koreader-ios/tree/a7cf2a98a28c6e70fb33087549bfb4a734ed19bc) |
| base | [hezi/koreader-base-ios@6e4bafc0a0619cd69e0961933524581ebed9ef0d](https://github.com/hezi/koreader-base-ios/tree/6e4bafc0a0619cd69e0961933524581ebed9ef0d) |
| crengine gitlink | `217341dd6e2f4cee995a9dfb5803a86e6ce320e7` |
| 宿主机 | Mac mini，Apple M4 Pro，64 GB；macOS 26.6.2 `25G83` |
| 工具链 | Xcode 27.1 `27A9275`，SDK 27.1，部署版本 27.0，arm64 `iphonesimulator`，Release，LuaJIT 解释器模式 |
| iPhone | iPhone 17 Pro Max，独立设备 `44843BD8-80B1-4CCB-895C-F0961135C285` |
| iPad | iPad Pro 11 英寸（M5，12 GB 模拟配置），独立设备 `9F2383FF-DE41-4644-BA93-93CF387DFFE6` |
| 实际运行时 | 两台均为 iOS 27.0 `24A434` |
| 实验 App | hezi KOReader，Bundle ID `rocks.koreader.ios`，不是最终 Just Reader 工程 |
| 样书 | owner iCloud Drive 的《蘋果之道》EPUB，只读复制为 `samples/apple.epub`，约 34 MiB |
| 样书 SHA-256 | `7e9c49d9aeed9e4138da8eba9fd289a21b073c46e7b66ce7cc1fb0898a245417` |

本机 iOS 27.1 `24A94425` 的 `supportedDeviceTypes` **只有 iPhone Duo**。用它创建两台目标机型均返回 `SimError 403: Incompatible device`。经 advisor `jr-86/2` 批准，改用支持目标机型的 27.0 运行时，仍用 Xcode 27.1 SDK 和部署版本 27.0；没有改运行时兼容元数据或换用 Duo。这满足 Q42 的 iOS 27 与 owner“性能必须在 27.x 上测”的要求。

以下性能数值来自上述宿主机的模拟器，仅为**临时门禁**。没有做 iPhone/iPad 真机、耗电或 Leaf5 实机验收；owner 按 [acceptance.md](acceptance.md#真机复核) 复核，真机不达标同样停下评估。

## 可复现的 Release 构建

审查并应用了 [hezi PR #11](https://github.com/hezi/koreader-ios/pull/11)，取样提交 `f8d29582a6e3f4b1230a705ca18984e57285aca3`：补全干净 clone 的 plist 生成、数字版本号、脚本 PATH 和 Xcode 脚本沙盒配置。其 iOS 15 设置没有照用，本实验统一为 27.0。

另补模拟器工程与 payload 路径、显式构建参数、桥符号保留/导出，并禁用可选宿主 Lua 字节码预编译。Xcode 会导出自己的 `INSTALL_DIR`，因此预构建也显式固定它，保证 make 和打包脚本使用同一暂存树。base 已有 SDK/triple 开关，本实验实际重新编译模拟器库，没有重标记真机库。

首次 Release 独立启动复现 `dlsym(RTLD_DEFAULT, ko_ios_get_safe_area_pixels): symbol not found`。只加 `-u` 后桥仍为局部 `t`；设置 `GCC_SYMBOLS_PRIVATE_EXTERN=NO` 并显式导出后，四个桥均为全局 `T`，App 可进入阅读画面。

将附录 A 的补丁保存为仓库外的 `phase-a.patch` 后执行：

```sh
brew install autoconf automake bash binutils cmake coreutils findutils \
  gettext gnu-getopt libtool make meson nasm ninja pkgconf sdl3 util-linux xcodegen
export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gnu-getopt/bin:/opt/homebrew/opt/make/libexec/gnubin:/opt/homebrew/opt/util-linux/bin:$PATH"
export DEVELOPER_DIR="/Applications/Xcode-27.1.0.app/Contents/Developer"
git clone --no-checkout https://github.com/hezi/koreader-ios.git phase-a
cd phase-a
git checkout a7cf2a98a28c6e70fb33087549bfb4a734ed19bc
git -c fetch.recurseSubmodules=false fetch --no-recurse-submodules \
  https://github.com/koreader/koreader.git tag v2026.03
git submodule update --init --depth 1 base resources/fonts l10n
git -C base submodule update --init --depth 1
test "$(git -C base rev-parse HEAD)" = 6e4bafc0a0619cd69e0961933524581ebed9ef0d
git apply ../phase-a.patch
make TARGET=ios IOS_PLATFORM=iphonesimulator IOS_DEPLOYMENT_TARGET=27.0 KODEBUG= xcodeproj
xcodebuild -project KOReader.xcodeproj -scheme KOReader -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ../DerivedData-phase-a CODE_SIGNING_ALLOWED=NO build
```

取固定上游 tag 是因为 hezi clone 没有可供 `git describe` 使用的发行 tag；生成版本为 `2026.03.70` / build `70`。第二个从 GitHub 新 clone 的 `clean-rebuild/` 已实际完成这些步骤，未复用第一次的 base 构建产物，日志末尾为 `** BUILD SUCCEEDED **` 和 `CLEAN_REBUILD_PASS`。`otool -l` 核对随包 Mach-O 的平台；主程序为 `LC_BUILD_VERSION platform 7 / minos 27.0 / sdk 27.1`。

实验区分构建与用途：干净基线只含附录 A；计时构建另加外部计时/命令驱动；审计构建再加 cdef/库句柄采集、原生 SDL watcher 和保存函数进入/退出日志；B5 设计原型另加生命周期入队、续时与 Lua 保存处理；Swift 静态探针是独立小 App。审计日志不用于性能表。冷/二次打开来自原计时构建；正式翻页值来自 B5 原型构建的 SDL 输入路径，关闭保存/cdef 审计。驱动不补保存逻辑。全部用 `simctl install` 与 `simctl launch --console-pty` 运行，console 是日志通道，没有调试器。

## EPUB 性能与连续阅读

冷打开清空独立 App 的 Documents，包括书籍设置、crengine/字体等应用缓存，再复制样书；没有清除 macOS 文件页缓存或 dyld 缓存。第二次打开保留数据，在终止进程后以同一路径重新启动；每项打开各采一例。

端到端计时从控制器开始启动流程（含容器查询和 `simctl`）到目标书籍首个实际画面，首次为封面；另保留原生 `SDL_main` 入口至首帧记录。两台均随后实际显示中文正文与彩色插图。

正式翻页从 `SDL_PushEvent` 注入 PageDown 的 key-down/up 前开始，到 `_repaint` 完成、SDL 提交画面后结束；每次确认页码变化。经过真实 SDL → 输入分发 → 阅读翻页路径，包含排队、分页、绘制与提交，**不含外部脚本传输、物理触摸和屏幕扫描输出**。每次渲染完成后才发起下一次。

| 指标 | 目标 | iPhone 17 Pro Max | iPad Pro 11 M5 | 判定 |
| --- | --- | --- | --- | --- |
| 冷打开，端到端 | ≤ 10 s | 1.370 s | 1.812 s | 通过 |
| 第二次打开，端到端 | ≤ 3 s | 1.414 s | 1.277 s | 通过 |
| 冷打开，原生入口至首帧（辅助值） | — | 0.744 s | 1.174 s | 不另设目标 |
| 第二次打开，原生入口至首帧（辅助值） | — | 0.717 s | 0.610 s | 不另设目标 |
| 30 次 SDL 输入翻页中位数 | ≤ 500 ms | 32.088 ms | 33.831 ms | 通过 |
| 30 次 SDL 输入翻页最慢值 | 记录 | 38.942 ms | 43.397 ms | 非新增门禁 |
| 连续阅读 ≥ 30 分钟 | 不崩溃 | 1800.214 s | 1800.201 s | 通过 |

三项性能采样时没有同时编译。两台连续阅读并行，每 15 秒注入真实 SDL 按键；每次记录 `InputEvent` 与 `screen_saver_mode=false`，不改自动休眠时间。宿主 `ps` 每约 30 秒记录进程存活和 RSS；这不是 iOS 真机峰值内存或耗电。连续阅读期间另有一次 Swift 原型增量构建和一次只读符号地址检查；没有切书或由驱动补保存，也未拿其间样本重算三项性能。

门禁连续阅读会话（15:35–16:05）运行在 B5 原型构建上，watcher 和生命周期入队均开启，与上述 SDL 输入翻页样本使用同一个构建。

清醒会话（均为 2026-10-25，SGT）：

| 设备 | 起止 | 翻页 / InputEvent | 进程与画面 | 宿主 RSS 采样范围 |
| --- | --- | --- | --- | --- |
| iPhone | 15:35:10.249–16:05:10.463 | 119 / 238 | PID 21050 保持，83→202 页 | 404528–441136 KiB |
| iPad | 15:35:10.521–16:05:10.722 | 119 / 240 | PID 21213 保持，83→203 页 | 407120–447904 KiB |

两台各有 120 次清醒状态采样，全部为 false（未进入 screen saver）；半程超过 15 分钟及结束截图均为实际正文/插图，没有休眠提示。日志无 Lua 退出或崩溃，结束前没有安装新构建或重启进程。监控 CSV 的首行页码默认写 1；上表起始 83 页取自 App 的 `soak_begin` 事件，不把该默认值当实测。

30 次翻页原始值，单位 ms：

```text
iPhone:
34.733 24.612 24.743 35.213 30.902 35.125 22.470 34.014 24.193 38.942
33.616 35.699 27.256 28.925 25.233 35.002 29.091 33.218 30.848 28.101
34.852 33.909 33.394 37.705 20.355 32.619 31.991 31.556 30.556 32.185
iPad:
43.397 30.695 29.629 34.132 25.633 39.676 34.336 24.176 32.032 33.516
30.052 34.160 33.618 31.726 35.204 32.930 36.664 35.699 36.184 31.530
19.949 23.680 28.184 40.058 37.426 34.044 39.813 36.214 25.557 36.490
```

## 进度、划线与生命周期

先保留原样 hezi 的观察。此轮沿用原计时/阅读构建，LuaSettings、DocSettings 与阅读保存代码没有改动；驱动只调用生产选区/划线 API，不调用保存帮助通过。每条划线带可辨识的想法标记，范围来自 crengine 实际正文选区。

| 场景 | iPhone | iPad |
| --- | --- | --- |
| 第 80 页、1 条划线，后台等待后回前台 | 80 页、1 条，范围/标记匹配 | 80 页、1 条，范围/标记匹配 |
| 第 81 页、2 条划线，系统锁屏后恢复 | 81 页、2 条，范围/标记匹配 | 该轮未完成 GUI 操作，不算通过 |
| 第 82 页、3 条划线，切后台等待约 5 秒后 `simctl terminate`，重新启动 | **第 56 页、0 条**，xpointer 不匹配 | **第 92 页、0 条**，xpointer 不匹配 |

这是实际的数据丢失。审计发现根因在事件交付：原生 watcher 收到 `259`（will-resign-active 映射的 WILL_ENTER_BACKGROUND）和 `260`（DID_ENTER_BACKGROUND），原版 Lua 没有收到生命周期事件，也没有进入保存函数。锁定 SDL3 的 `src/events/SDL_events.c:SDL_SendAppEvent()` 对这些事件明确只调用 watcher，**不放入 SDL 队列**。因此 hezi 的 `ffi/SDL3.lua` 虽有生命周期分支，实际无法经 `SDL_WaitEventTimeout` 收到它们。这不是原地写入被中断的证据。

Q48 将判定对象明确为 ADR-0009 的保存设计。仓库外 B5 原型在 watcher 申请 UIKit 后台续时，把原事件码封装进 `SDL_EVENT_USER` 入队；Lua 在正常主循环取出，设备层同步调用 `UIManager:flushSettings()`、当前 `ReaderUI:saveSettings()`，完成后调用原生桥结束续时。原生回调不执行 Lua；LuaSettings/DocSettings 原写入算法保持不变。首轮原型用 hezi 原生文件验证队列通路，随后新增桥改为 Swift `@c`，遵循 ADR-0010；正式 B5 仍须实现失效/过期标志、回前台补做、合并保存和原子写入。

首轮原型的相同流程已完成两台复验，原有一条划线保留为起点：

| 场景 | 两台的预期与实际 |
| --- | --- |
| 新划线后后台约 5 秒、直接返回 | 81 页、2 条 → 81 页、2 条 |
| 再加划线、系统锁屏与唤醒 | 82 页、3 条 → 82 页、3 条 |
| 再加划线、后台约 5 秒、终止重开 | 83 页、4 条 → 83 页、4 条 |

三次进度的 xpointer 匹配；重开后的新增划线 note、pos0、pos1、underline 类型逐项匹配。原生记录续时有效、Lua 记录出队和保存完成、原生记录结束续时；重复 UIKit/scene 通知会重复保存，正式 B5 应合并。

Swift `@c` 原型也完成两台复验。此前探针留下的划线基数不同；以下每格均为本轮预期与实际相同的结果：

| 场景 | iPhone | iPad |
| --- | --- | --- |
| 新划线 → 后台约 5 秒 → 返回 | 87 页、8 条 → 相同 | 85 页、6 条 → 相同 |
| 再加划线 → Device → Lock → 唤醒 | 88 页、9 条 → 相同 | 86 页、7 条 → 相同 |
| 再加划线 → 后台约 5 秒 → 终止重开 | 90 页、10 条 → 相同 | 87 页、8 条 → 相同 |

正式日志为 `b5-swift-formal` 与 `b5-swift-restart*`：核对 `apple.epub` 路径、真实页码、xpointer 和每条新划线的标记/范围/类型，且直接后台返回前后进程保持。锁屏前与解锁后的样书画面、系统锁屏画面均核对。Swift 的续时开始、Lua 主循环出队与同步保存、原生结束续时全部发生。

两段操作失误未计入通过依据，原始日志保留：GUI 预演被 Esc 操作打断后，无样书参数的启动进入了 QuickStart；正式复验重新显式启动样书并加文档路径断言。另一次 iPhone 第 89 页是纯图，驱动未选到文字，未产生新划线；改选相邻有正文的第 90 页后，重新执行完整后台终止流程。没有把这次无划线的尝试算作通过，也没有用驱动调用保存。

首次连续会话每台持续约 1800 秒、119 次直接 `GotoViewRel` 翻页：iPhone 14:30:08–15:00:08、iPad 14:30:51–15:00:51（SGT）。截图发现第 15 分钟后出现 SDL 模拟器自动休眠提示，因为直接调用没有更新输入活动计时。该轮 **不计入连续阅读门禁**；宿主 RSS 采样范围分别为 274768–433120、283040–295808 KiB，只保留为原始观察。对应直接翻页 30 次中位数为 21.793/24.492 ms，最慢 26.807/32.586 ms；正式门禁使用上表较完整的 SDL 输入值。

## FFI 符号清单雏形

以实际启用的模块为边界，按 Q35 分四类，不把全仓平台 cdef 自动并入发行清单。

| 类别 | 清单与方法 | 本次结果 |
| --- | --- | --- |
| 一：原生桥 | `ko_ios_get_safe_area_pixels`、`ko_ios_pick_folder_start`、`ko_ios_pick_folder_poll`、`ko_ios_resolve_bookmark`；全局导出 + `ffi.C` | **4/4**，`nm` 全局 `T`，两台实际解析成功 |
| 二：base | SDL3、BlitBuffer、FreeType/HarfBuzz、归档、字符处理、SQLite、MuPDF/KOPT 等；含 3 个 MuPDF 全局数据和 13 个 Lua C 入口 | **392/392**，两台解析成功；现有 dylib 打包允许，最终全静态归 B1 |
| 三：系统库 | 内存、文件、时间、网络等由 dyld 解析的系统 API | **74/74**，两台解析成功；发行实现按 Q35 只在 Debug 自检 |
| 四：未启用能力 | 此次公共声明中 21 个 Windows/Linux/FBInk 名称，以及 17 个进程/伪终端 API | 前 21 个不可解析且路径不适用；后 17 个有地址但不据此开放能力 |

完整名称见附录 C，本地 `ffi-manifest.csv` 另保存来源、类别和解析库。审计覆盖启动、EPUB、划线、PDF/KOPT 加载的声明，再补 MuPDF 全局数据与编译入库的 Lua C 入口。初始正则产生的 `int` / `void` 两条伪符号已人工剔除；没有把整仓平台头文件自动并入。有效门禁范围为类一至三共 **470 项，全数可解析**；类四有地址的 17 项也实际核对了地址。因此除 21 个不适用平台声明外，没有把真实解析失败藏入类别四。另有两项实验附加符号单列，不算产品 API。

解析先尝试 `ffi.C[name]`，再尝试实际加载的库句柄；两台的可解析/不可解析结果一致，库句柄别名可能因枚举顺序不同。`sqlite3_close` 与 `sqlite3_result_null` 当前由系统 dyld 补齐，随包 monolibtic 的 `nm` 没有这两个导出；它们按 API 所属仍列类二。按 advisor `jr-86/1` 的 T0 口径，现有打包可解析即通过，但 B1 不能拿系统补齐冒充全静态成功，须显式保留完整 SQLite API 并检查跨库解析。其余 base 项同时对照随包导出表。13 个 Lua C 入口均有全局导出和可解析地址；运行记录另含 `lfs`、`nnsvg`、`xtext`、`lpeg`、`rapidjson`、socket/mime/SSL 的实际加载，独立静态探针验证 preload 注册。

这里只核对声明/入口能解析；函数地址存在不证明每项平台能力都可运行。B1 须形成静态链接最终清单、显式保留与注册表，并以缺符号即失败的门禁重验。

## Swift 静态链接探针

**通过，未发现原理性障碍。** 单独 UIKit Release App 静态链接本次 base 构建的 `libluajit-5.1.a` 与 `libz.a`，Swift 导出：

```swift
@c(ko_ios_phase_a_probe)
public func phaseAProbe() -> Int32 { 86 }
```

保留 `-u,_ko_ios_phase_a_probe`、`-u,_zlibVersion` 并启用导出，保持 Release dead stripping。通过 `package.preload` 注册编译好的 `phase_a` Lua C 模块，它调用静态 zlib 返回版本。Swift 使用 `luaL_loadstring` + `lua_pcall`，不依赖函数式宏。Lua 实际执行：

```lua
local ffi = require("ffi")
ffi.cdef[[int ko_ios_phase_a_probe(void); const char *zlibVersion(void);]]
assert(jit.status() == false)
assert(ffi.C.ko_ios_phase_a_probe() == 86)
assert(require("phase_a").version == ffi.string(ffi.C.zlibVersion()))
```

模拟器输出 `STATIC_PROBE_PASS jit=false sentinel=86 zlib=1.3.2 module=phase_a`，原生 status 为 0。最终 `nm -gU` 含 `_ko_ios_phase_a_probe`、`_luaL_newstate`、`_zlibVersion`；`otool -L` 没有 LuaJIT/zlib dylib 依赖，仅 Apple 系统库/框架与系统 Swift 库。

这证明最小 C ABI 保留、解释器 FFI 和 Lua C 模块注册路径可行，没有把完整 crengine/MuPDF/SDL 改成最终静态交付。完整静态依赖闭包、注册表、导出清单和 Tuist 接入仍归 B1，不把这部分未完成算成 T0 独立失败。

## 其余技术未知数

### 系统中文字体

两台 App 沙盒均实际读到 TTC 头 `ttcf`，并成功调用 `cre.registerFont()` 注册：

| 文件 | crengine 结果 |
| --- | --- |
| `/System/Library/Fonts/STHeiti Medium.ttc` | 成功，枚举到 Heiti SC / Heiti TC |
| `/System/Library/Fonts/STHeiti Light.ttc` | 成功 |
| `/System/Library/Fonts/Supplemental/Songti.ttc` | 成功，枚举到 STSong / Songti SC / Songti TC |
| `/System/Library/Fonts/CJKSymbolsFallback.ttc` | 文件可读，注册失败，不能当作正文中文字体 |

另用公开 CoreText API 查询 PingFang SC/TC：`CTFontCreateWithName` → `CTFontCreateForString` → `kCTFontURLAttribute`，获得运行时挂载区的 `FontServices.framework/CorePrivate/PingFangUI.ttc` URL。Lua 可读该 URL 对应文件，但 crengine 拒绝注册；只把目录名改成 `/System/Library/PrivateFrameworks/...` 也不存在。没有调用私有 framework API，也没有据文件名假定可用。B1 应经 CoreText 找文件并实测，不能硬编码此次模拟器挂载路径，PingFang 兼容原因仍须后续查明。

样书有内嵌中文字体，包内另有 `NotoSansCJKsc-Regular.otf`；正文显示正常只作为阅读证据。上述独立注册结果才证明至少 Heiti/Songti 的系统文件可由 crengine 使用。真机字体资产与文件保护仍须 owner 复核。

### KOPT 与 PDF

已生成并渲染检查一页文字 PDF 和一页无文本层的纯图像扫描 PDF，均为自行生成的 40 行英文短句。两台 Release 中实际由 MuPDF 打开并显示，调用生产 `KoptInterface:reflowPage(doc, 1, bbox, false)`：`getPagePix` → `k2pdfopt_reflow_bmp` → `dstToBlitBuffer` → PNG。位图均非空，已检查导出图像中的可读文字；这里只证明前台内存重排通路，复杂版式、中文质量和参数尚未验收。

| PDF | iPhone 耗时 / 输出 | iPad 耗时 / 输出 |
| --- | --- | --- |
| 有文本层 | 245.817 ms / 1320×14663，24 bpp | 357.575 ms / 1668×17298，24 bpp |
| 纯图像扫描 | 79.018 ms / 1320×2563，24 bpp | 104.830 ms / 1668×3238，24 bpp |

这些是 KOPT 调用自身的单次诊断值，不是 EPUB 翻页性能门禁。`k2pdfopt_reflow_bmp` 在随包库可解析。hezi 对 willuslib 的 `system()` 改为 `(0)` 影响未经过 KOReader FFI 的 CLI/GUI 路径，没有阻止此次内存重排；不能把 fork/外部命令不可用等同于 KOPT 算法能力不可用。结论为**本锁定版本的前台内存重排可用，没有发现算法能力障碍**。据此判断剩余工作属于构建/平台接入，可进入条件票 C5（#101）；这不追认以往特定失败的根因。首版仍按 Q20 隐藏重排入口，不启用后台重排或缩略图子进程。

### LuaSettings/DocSettings

**文档前提有误。** 锁定 hezi 与本 worktree 的 `LuaSettings:flush()` 均先 `backup()`，再 `util.writeToFile()`；后者直接 `io.open(filepath, "wb")` 原地写入、同步、关闭。只有文件修改时间超过 60 秒，`backup()` 才改名为 `.old`。DocSettings 写 `.sdr` 也没有临时文件原子替换。

原 Q36/ADR-0009 把“临时文件 + fsync + rename + .old”描述为既有实现不准确；Q47 已更正，并把实现补全放入 B5（#93）。本票不改算法，也不因缺少算法单独判 no-go；生命周期持久化门禁按 Q48 的设计原型判定。

两台的独立 LuaSettings 文件均得到：首次写 generation=1，60 秒内再写 2 时无 `.old`；把 mtime 设为超过 60 秒后写 3，主文件=3、`.old`=2；故意破坏主文件后 `LuaSettings:open()` 回退到 2。`fsyncOpenedFile()` 与目录 fsync 均实际返回 true。

独立的原语实验再执行完整临时文件写入/flush/fsync、旧主文件改名 `.old`、临时文件改名主文件、目录 fsync，得到主文件=2、备份=1。在三个明确检查点用 `simctl terminate` 后重开，两台结果一致：

| 中断点 | 实际恢复 |
| --- | --- |
| 临时文件只写了一半，主文件尚未改名 | 主文件旧完整版本 1 |
| 新临时文件已 fsync，主文件已改名 `.old`，尚未提升新文件 | 从 `.old` 恢复旧完整版本 1 |
| 新文件已提升并完成目录 fsync | 新完整版本 2 |

这些只操作专用 `phase-a-*` 文件，不参与阅读门禁数据保存；证实的是模拟器文件系统上的原语和恢复路径，**不证明现有 App 已实现原子保存，也不等价于真实断电耐久性**。

### point、pixel 与 dp

运行中调用 `SDL_GetWindowSize` / `SDL_GetWindowSizeInPixels`，再记录 `Device.screen`、DPI 和 `scaleBySize(44)`：

| 设备 | 窗口 point | 窗口 pixel | KOReader 安全区画布 pixel | 当前 DPI / 44dp |
| --- | --- | --- | --- | --- |
| iPhone | 440×956 | 1320×2868 | 1320×2580 | 160 / 97px≈32.3pt |
| iPad | 834×1210 | 1668×2420 | 1668×2380 | 160 / 123px=61.5pt |

现有 SDL 缩放尚不满足 1dp≈1pt，尤其 iPhone 的 44dp 触控框不足 44pt；这是 B4 的既定接入工作，不把窗口像素当成 UIKit point。没有为了本票修改 DPI 或控件尺寸。

## 后续与证据

B1 要在已合入的 D0 Swift + UIKit / Tuist 工程上接入，不能把本实验 xcodegen 工程转成正式入口：

| hezi 参考实现 | 后续 Swift 重写 / 接入边界 |
| --- | --- |
| `ios_loader.m` | 唯一 Lua VM、SDL_main 启动、搜索路径、环境变量、沙盒目录与资源加载 |
| `ko_ios_get_safe_area_pixels` | UIKit scene/window 的 point 与 pixel 转换、安全区与尺寸变化，保持 `@c` ABI |
| `ios_filepicker.m` 的 picker / bookmark | 原生系统控制器与可轮询状态；正式三条导入走复制到 Documents，不照搬授权目录原地阅读 |
| 生命周期 watcher | Swift 续时/入队桥，Lua 主循环保存；B5 完成失效/过期、前台补做、合并保存及原子写入 |
| dylib 与动态 Lua C 加载 | B1 全静态依赖闭包、显式符号保留与 Lua C 注册表，特别消除 SQLite 的系统补齐依赖 |

B4 仍须实现 dp/point 规则；C5 仍须验证真实 PDF 的重排质量。真机速度、真实内存回收、耗电、文件保护与系统交互由 owner 复核。这些后续交付物不能用本次最小探针代替。

仓库 spec 按 Q46 未运行，没有做 Leaf5 验收；构建、模拟器运行、计时、翻页及证据渲染照常执行。用例在 [acceptance.md](acceptance.md)。

本地证据根目录为 `/Volumes/T5/github/ios-phase-a/evidence/`，不作为公开下载链接。下表的 `.tsv` 和 console 日志中嵌有宿主机的模拟器容器路径，以后不能原样贴到公开 issue，须先脱敏：

| 证据 | 文件 |
| --- | --- |
| 干净重建 | `clean-rebuild.log`，末尾 `CLEAN_REBUILD_PASS` |
| 缺符号及修复 | `baseline-console-01.log`、`baseline-console-03.log`、`xcodebuild-baseline-05.log` |
| 打开性能与初次直接翻页 | `*-cold-open.json`、`*-warm-open.json`、`*-30-turns.json` |
| SDL 输入翻页 | `*-input-30-turns.json`、`*-input-turns.log` |
| 首次休眠会话，不计门禁 | `*-warm-console.log`、`soak-monitor.csv`、`soak-summary.json`、`*-soak-events.tsv` |
| 清醒连续阅读 | `*-awake-soak-console.log`、`awake-soak-monitor.csv`、`awake-soak-monitor.log`、`awake-soak-summary.json`、`*-awake-soak-events.tsv` |
| 原样 hezi 数据丢失 | `*-persistence-failure/events.tsv` 及 `.sdr`、`*-gate-restart-console.log` |
| B5 首轮原型 | `*-b5-gates-fixed-console.log`、`*-b5-restart-console.log`、`validated-evidence.json` |
| B5 Swift 原型 | `b5-swift-build.log`、`*-b5-swift-formal-console.log`、`*-b5-swift-restart*-console.log`、`swift-persistence-summary.json`、`*-swift-persistence/` |
| Swift 静态探针 | `static-console-pty.log`、`static-nm.txt`、`static-otool.txt` |
| 字体与原始生命周期 | `*-audit-observe-console.log`、`*-b5-restart-console.log`、`font-query.log`、`*-pdf-text-console.log` |
| 存储与中断原语 | `storage-checkpoints.log`、`*-checkpoint-*-console.log`、`validated-evidence.json` |
| FFI | `ffi-manifest.csv`、`*-symbols-extended.tsv`、`*-swift-symbols-extended.tsv`、`data-and-lua-entry-nm.txt` |
| 画面与 PDF | `phase-a-*-awake-mid.png`、`phase-a-*-b5-lock.png`、`*-phase-a-*.pdf.reflow.png`、`pdf-*-1.png` |
| 探针代码快照哈希 | `probe-source-sha256.json` |

## 附录 A：干净构建完整补丁

只用于 hezi 的一次性验证，不是正式 Swift/Tuist 实现；不含计时、翻页、watcher 或存储探针。

<!-- PHASE_A_REPRODUCTION_PATCH -->

```diff
diff --git a/make/ios.mk b/make/ios.mk
index ba250ded8..7c97d689b 100644
--- a/make/ios.mk
+++ b/make/ios.mk
@@ -17,11 +17,34 @@ ios-check-prereqs:
 update: ios-check-prereqs all
 	$(CURDIR)/platform/ios/do_ios_bundle.sh $(INSTALL_DIR)

+# Bundle identifier baked into Info.plist. Must match
+# PRODUCT_BUNDLE_IDENTIFIER in platform/ios/project.yml.
+IOS_BUNDLE_ID ?= rocks.koreader.ios
+
+# CFBundleShortVersionString has to be a dotted numeric string; the raw
+# `git describe` output (v2026.03-70-gabc123_2026-04-27) is not, and iOS
+# rejects the bundle at install time. Split the describe into the tag and
+# the commits-ahead count: v2026.03-70-g... -> 2026.03.70 / build 70.
+KO_VER_PARTS := $(subst -, ,$(patsubst v%,%,$(VERSION)))
+IOS_SHORT_VERSION := $(word 1,$(KO_VER_PARTS)).$(or $(word 2,$(KO_VER_PARTS)),0)
+IOS_BUNDLE_VERSION := $(or $(word 2,$(KO_VER_PARTS)),0)
+
+# platform/ios/Info.plist is gitignored and generated. project.yml points
+# INFOPLIST_FILE at it, so it must exist before xcodegen runs -- a fresh
+# clone has only Info.plist.in.
+$(IOS_DIR)/Info.plist: $(IOS_DIR)/Info.plist.in
+	@echo "Generating $@ (version $(IOS_SHORT_VERSION), build $(IOS_BUNDLE_VERSION), id $(IOS_BUNDLE_ID))"
+	@sed -e 's|@BUNDLE_ID@|$(IOS_BUNDLE_ID)|g' \
+	     -e 's|@SHORT_VERSION@|$(IOS_SHORT_VERSION)|g' \
+	     -e 's|@BUNDLE_VERSION@|$(IOS_BUNDLE_VERSION)|g' \
+	     -e 's|@VERSION@|$(IOS_SHORT_VERSION)|g' \
+	     $< > $@
+
 # Generate KOReader.xcodeproj at the repo root from platform/ios/project.yml.
 # Depends on `all` so the staging tree + base/build/<machine>/libs/ exist
 # (the project's pre-build script also calls `make TARGET=ios base`, but
 # having them present at generation time avoids confusing first-time errors).
-xcodeproj: ios-check-prereqs all
+xcodeproj: ios-check-prereqs all $(IOS_DIR)/Info.plist
 	xcodegen generate \
 		--spec $(IOS_DIR)/project.yml \
 		--project $(CURDIR) \
diff --git a/platform/ios/Info.plist.in b/platform/ios/Info.plist.in
index 0a51548e0..920ee0143 100644
--- a/platform/ios/Info.plist.in
+++ b/platform/ios/Info.plist.in
@@ -9,7 +9,7 @@
     <key>CFBundleExecutable</key>
     <string>KOReader</string>
     <key>CFBundleIdentifier</key>
-    <string>rocks.koreader.ios</string>
+    <string>@BUNDLE_ID@</string>
     <key>CFBundleInfoDictionaryVersion</key>
     <string>6.0</string>
     <key>CFBundleName</key>
@@ -17,15 +17,15 @@
     <key>CFBundlePackageType</key>
     <string>APPL</string>
     <key>CFBundleShortVersionString</key>
-    <string>@VERSION@</string>
+    <string>@SHORT_VERSION@</string>
     <key>CFBundleVersion</key>
-    <string>1</string>
+    <string>@BUNDLE_VERSION@</string>
     <key>CFBundleSignature</key>
     <string>????</string>
     <key>LSRequiresIPhoneOS</key>
     <true/>
     <key>MinimumOSVersion</key>
-    <string>14.0</string>
+    <string>27.0</string>
     <key>UIDeviceFamily</key>
     <array>
         <integer>1</integer>
diff --git a/platform/ios/do_ios_bundle.sh b/platform/ios/do_ios_bundle.sh
index 152a0fa3b..0ec54b441 100755
--- a/platform/ios/do_ios_bundle.sh
+++ b/platform/ios/do_ios_bundle.sh
@@ -102,7 +102,21 @@ rsync -aL \

 # 3) Generate Info.plist with version filled in.
 echo "[*] Writing Info.plist"
-sed "s|@VERSION@|${VERSION#v}|g" \
+# CFBundleShortVersionString must be dotted-numeric: turn
+# v2026.03-70-gabc123_2026-04-27 into 2026.03.70 (build 70).
+_ver="${VERSION#v}"
+KO_TAG="${_ver%%-*}"
+_rest="${_ver#*-}"
+KO_AHEAD="${_rest%%-*}"
+case "${KO_AHEAD}" in
+    ''|*[!0-9]*) KO_AHEAD=0 ;;
+esac
+SHORT_VERSION="${KO_TAG}.${KO_AHEAD}"
+BUNDLE_ID="${IOS_BUNDLE_ID:-rocks.koreader.ios}"
+sed -e "s|@BUNDLE_ID@|${BUNDLE_ID}|g" \
+    -e "s|@SHORT_VERSION@|${SHORT_VERSION}|g" \
+    -e "s|@BUNDLE_VERSION@|${KO_AHEAD}|g" \
+    -e "s|@VERSION@|${SHORT_VERSION}|g" \
     "${PLATFORM_DIR}/Info.plist.in" >"${APP_BUNDLE}/Info.plist"

 printf 'APPL????' >"${APP_BUNDLE}/PkgInfo"
diff --git a/platform/ios/embed-bundle-payload.sh b/platform/ios/embed-bundle-payload.sh
index 42f8d8379..861a42031 100755
--- a/platform/ios/embed-bundle-payload.sh
+++ b/platform/ios/embed-bundle-payload.sh
@@ -15,12 +15,12 @@ set -euo pipefail

 # Override per-config / per-arch if needed; defaults match make/ios.mk.
 IOS_ARCH="${IOS_ARCH:-arm64}"
-IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-14.0}"
+IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-27.0}"

 APP_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
-STAGING="${SRCROOT}/koreader-ios-${IOS_ARCH}-apple-ios${IOS_DEPLOYMENT_TARGET}"
+STAGING="${SRCROOT}/koreader-ios-arm64-apple-ios27.0-simulator"
 STAGING_KOREADER="${STAGING}/koreader"
-LIBS_SRC="${SRCROOT}/base/build/${IOS_ARCH}-apple-ios${IOS_DEPLOYMENT_TARGET}/libs"
+LIBS_SRC="${SRCROOT}/base/build/arm64-apple-ios27.0-simulator/libs"

 if [ ! -d "${STAGING_KOREADER}" ]; then
     echo "error: staging tree not found at ${STAGING_KOREADER}" >&2
@@ -55,7 +55,7 @@ rsync -aL --delete \

 # --- 1.5) Precompile every .lua to LuaJIT bytecode in place. Skips if
 # we don't have a host luajit available; only a perf optimisation.
-"${SRCROOT}/platform/ios/precompile-lua.sh" "${APP_DIR}/app" || true
+# Phase A baseline: ship source Lua, no optional bytecode precompile.

 # --- 2) Re-sign every embedded dylib with the same identity as the app.
 # Pick the most-resolved identity Xcode passed us, falling back to ad-hoc
diff --git a/platform/ios/precompile-lua.sh b/platform/ios/precompile-lua.sh
index 41054ff86..cf2cfbd9e 100755
--- a/platform/ios/precompile-lua.sh
+++ b/platform/ios/precompile-lua.sh
@@ -26,8 +26,11 @@ REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
 # version + features as the iOS target), then fall back to PATH.
 HOST_LUAJIT=""
 HOST_LUAJIT_SHARE=""
-for machine in arm64-apple-darwin25.0.0 arm64-apple-darwin24.0.0 \
-               x86_64-apple-darwin25.0.0 x86_64-apple-darwin24.0.0; do
+# Glob rather than hardcode the darwin version: the host triple tracks the
+# running macOS kernel (darwin24 = macOS 15, darwin25 = 26, darwin27 = 27...),
+# so a fixed list silently stops matching on every new macOS release.
+for cand_dir in "${REPO_ROOT}"/base/build/*-apple-darwin*; do
+    machine="$(basename "${cand_dir}")"
     cand="${REPO_ROOT}/base/build/${machine}/luajit"
     share="${REPO_ROOT}/base/build/${machine}/staging/share/luajit-2.1"
     if [ -x "$cand" ] && [ -d "$share" ]; then
diff --git a/platform/ios/project.yml b/platform/ios/project.yml
index 82b623a5b..91167eb9a 100644
--- a/platform/ios/project.yml
+++ b/platform/ios/project.yml
@@ -2,7 +2,7 @@ name: KOReader
 options:
   bundleIdPrefix: rocks.koreader
   deploymentTarget:
-    iOS: "14.0"
+    iOS: "27.0"
   createIntermediateGroups: true
   developmentLanguage: en
   # The project lives at the repo root so paths in `sources`/`scripts`
@@ -12,13 +12,22 @@ options:
 settings:
   base:
     ENABLE_BITCODE: NO
-    SWIFT_VERSION: "5.0"
+    GCC_SYMBOLS_PRIVATE_EXTERN: NO
+    # The build phases below shell out to KOReader's Makefile, which reads
+    # and writes across SRCROOT and base/. Those accesses cannot be declared
+    # as script inputs/outputs, so Xcode's user-script sandbox (default YES
+    # since Xcode 26) denies them with "Operation not permitted".
+    ENABLE_USER_SCRIPT_SANDBOXING: NO
+    SWIFT_VERSION: "6.0"
+    IOS_PLATFORM: iphonesimulator
+    IOS_DEPLOYMENT_TARGET: "27.0"
+    ENABLE_DEBUG_DYLIB: NO
     # Skip the simulator slice for now — base/ libs are device-only.
-    SUPPORTED_PLATFORMS: iphoneos
+    SUPPORTED_PLATFORMS: iphonesimulator
     ONLY_ACTIVE_ARCH: YES
     ARCHS: arm64
     VALID_ARCHS: arm64
-    IPHONEOS_DEPLOYMENT_TARGET: "14.0"
+    IPHONEOS_DEPLOYMENT_TARGET: "27.0"
     # Personal team / free-cert signing: leave team blank so each user
     # can fill it in via the Xcode UI. Manual style avoids the
     # capabilities-spam Xcode does under Automatic.
@@ -46,12 +55,21 @@ targets:
         # produced by `make TARGET=ios base`. The pre-build script makes
         # sure that's up-to-date before we start compiling.
         HEADER_SEARCH_PATHS:
-          - $(SRCROOT)/base/build/arm64-apple-ios14.0/staging/include
-          - $(SRCROOT)/base/build/arm64-apple-ios14.0/staging/include/luajit-2.1
+          - $(SRCROOT)/base/build/arm64-apple-ios27.0-simulator/staging/include
+          - $(SRCROOT)/base/build/arm64-apple-ios27.0-simulator/staging/include/luajit-2.1
         LIBRARY_SEARCH_PATHS:
-          - $(SRCROOT)/base/build/arm64-apple-ios14.0/libs
-          - $(SRCROOT)/base/build/arm64-apple-ios14.0/staging/lib
+          - $(SRCROOT)/base/build/arm64-apple-ios27.0-simulator/libs
+          - $(SRCROOT)/base/build/arm64-apple-ios27.0-simulator/staging/lib
         OTHER_LDFLAGS:
+          - -Wl,-export_dynamic
+          - -Wl,-exported_symbol,_ko_ios_get_safe_area_pixels
+          - -Wl,-exported_symbol,_ko_ios_pick_folder_start
+          - -Wl,-exported_symbol,_ko_ios_pick_folder_poll
+          - -Wl,-exported_symbol,_ko_ios_resolve_bookmark
+          - -Wl,-u,_ko_ios_get_safe_area_pixels
+          - -Wl,-u,_ko_ios_pick_folder_start
+          - -Wl,-u,_ko_ios_pick_folder_poll
+          - -Wl,-u,_ko_ios_resolve_bookmark
           - -lluajit
           - -lSDL3
         # rpath so dyld finds the dylibs we copy into app/libs at post-build.
@@ -71,14 +89,18 @@ targets:
       - name: Build base/ libs and staging tree
         script: |
           set -euo pipefail
-          # Xcode strips PATH down. Reinstate Homebrew GNU tools used by
-          # KOReader's Makefile.
-          export PATH="$(brew --prefix)/opt/findutils/libexec/gnubin:$(brew --prefix)/opt/gnu-getopt/bin:$(brew --prefix)/opt/make/libexec/gnubin:$(brew --prefix)/opt/util-linux/bin:${PATH}"
+          # Xcode strips PATH down to the launchd default, which does NOT
+          # contain Homebrew -- so `brew` itself has to be found first, before
+          # it can be used to locate the GNU tools KOReader's Makefile needs.
+          # (Building from a terminal masks this: the shell's PATH is inherited.)
+          export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
+          BREW_PREFIX="$(brew --prefix)"
+          export PATH="${BREW_PREFIX}/opt/findutils/libexec/gnubin:${BREW_PREFIX}/opt/gnu-getopt/bin:${BREW_PREFIX}/opt/make/libexec/gnubin:${BREW_PREFIX}/opt/util-linux/bin:${PATH}"
           cd "${SRCROOT}"
           # `all` (not `base`) so the koreader-ios-…/koreader staging
           # tree gets assembled too — the post-build script rsyncs from
           # there into the .app.
-          make TARGET=ios all
+          make TARGET=ios IOS_PLATFORM=iphonesimulator IOS_DEPLOYMENT_TARGET=27.0 KODEBUG= INSTALL_DIR=koreader-ios-arm64-apple-ios27.0-simulator all
         basedOnDependencyAnalysis: false
     postBuildScripts:
       - name: Embed assets and dylibs
```

## 附录 B：仓库外 B5 原型接缝

这是设计可行性探针，不是完整 B5 实现。以下 Swift 文件使用桥接头 `#include <SDL3/SDL.h>`；由 hezi 现有安全区初始化入口调用 `ko_ios_phase_a_install()` 安装 watcher。项目加入 Swift 源文件，给 `ko_ios_phase_a_install` / `ko_ios_phase_a_background_end` 配置与附录 A 相同的 `-u` 和显式导出；Release dead stripping 保持开启。

```swift
import Foundation
import UIKit

@MainActor
private enum B5Prototype {
    static var task = UIBackgroundTaskIdentifier.invalid
    static var installed = false

    static func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
        print("[PHASE_A_B5] background_task_end")
    }

    static func observe(_ type: UInt32) {
        print("[PHASE_A_NATIVE] \(Date().timeIntervalSince1970) event=\(type)")
        if type == SDL_EVENT_WILL_ENTER_BACKGROUND.rawValue || type == SDL_EVENT_DID_ENTER_BACKGROUND.rawValue {
            if task == .invalid {
                task = UIApplication.shared.beginBackgroundTask(withName: "Phase A B5 prototype") {
                    print("[PHASE_A_B5] background_task_expired")
                    end()
                }
                print("[PHASE_A_B5] background_task_begin valid=\(task != .invalid) main=\(Thread.isMainThread)")
            }
        }
        var queued = SDL_Event()
        queued.type = SDL_EVENT_USER.rawValue
        queued.user.code = Int32(type)
        print("[PHASE_A_B5] enqueue=\(type) ok=\(SDL_PushEvent(&queued))")
    }

    static func install() {
        guard !installed else { return }
        installed = SDL_AddEventWatch({ _, pointer in
            guard let pointer else { return true }
            let type = pointer.pointee.type
            if type >= SDL_EVENT_TERMINATING.rawValue && type <= SDL_EVENT_DID_ENTER_FOREGROUND.rawValue {
                // UIKit lifecycle callbacks are on the main thread. Never reenter Lua.
                precondition(Thread.isMainThread)
                MainActor.assumeIsolated { B5Prototype.observe(type) }
            }
            return true
        }, nil)
        print("[PHASE_A_NATIVE] watcher_installed=\(installed)")
    }
}

@c(ko_ios_phase_a_install)
public func phaseAInstall() {
    if Thread.isMainThread { MainActor.assumeIsolated { B5Prototype.install() } }
    else { DispatchQueue.main.async { B5Prototype.install() } }
}

@c(ko_ios_phase_a_background_end)
public func phaseAEnd() {
    if Thread.isMainThread { MainActor.assumeIsolated { B5Prototype.end() } }
    else { DispatchQueue.main.async { B5Prototype.end() } }
}
```

`ffi/SDL3.lua` 在 `SDL_EVENT_USER` 中取 `event.user.code`，转换为 `EV_SDL`；不把原生 watcher 变成 Lua FFI callback。Lua 设备事件处理的保存接缝为：

```lua
-- ev.code 为 SDL_EVENT_WILL_ENTER_BACKGROUND 或 SDL_EVENT_DID_ENTER_BACKGROUND
local ffi = require("ffi")
ffi.cdef[[void ko_ios_phase_a_background_end(void);]]
UIManager:flushSettings()
local ReaderUI = require("apps/reader/readerui")
if ReaderUI.instance then ReaderUI.instance:saveSettings() end
ffi.C.ko_ios_phase_a_background_end()
```

实际代码另有原生时间戳、Lua 出队/保存起止记录；测量驱动只发输入、选区/划线和观察状态，没有调用上述保存接口。这个原型没有实现续时失败/过期后的优先级、未完成标记和合并策略，不能作为正式 B5 直接合入。

## 附录 C：FFI 清单雏形

按实际加载声明、函数地址解析、导出表和平台分支复核后的快照；不是全仓 cdef 扫描结果。base 类还列出 3 个 MuPDF 全局数据与 13 个 Lua C 入口。B1 必须重新按启用能力生成最终列表，不能直接把此处文本复制为静态链接保留清单。

### 一：桥（4）

```text
ko_ios_get_safe_area_pixels ko_ios_pick_folder_poll ko_ios_pick_folder_start ko_ios_resolve_bookmark
```

### 二：base API / 数据 / Lua C 入口（392）

```text
BB_add_blit_from BB_alpha_blit_from BB_blend_RGB32_multiply_rect BB_blend_RGB32_over_rect
BB_blend_RGB_multiply_rect BB_blend_rect BB_blit_to BB_color_blit_from BB_color_blit_from_RGB32
BB_dither_alpha_blit_from BB_dither_blit_to BB_dither_pmulalpha_blit_from BB_fill BB_fill_rect
BB_fill_rect_RGB32 BB_hatch_rect BB_invert_blit_from BB_invert_rect BB_paint_rounded_corner
BB_pmulalpha_blit_from FT_Activate_Size FT_Done_Face FT_Done_Library FT_Done_Size FT_Get_Char_Index
FT_Get_Kerning FT_Get_Sfnt_Table FT_GlyphSlot_Embolden FT_GlyphSlot_Oblique FT_Init_FreeType
FT_Load_Char FT_Load_Glyph FT_MulFix FT_New_Face FT_New_Size FT_Outline_Embolden
FT_Outline_Translate FT_Reference_Face FT_Reference_Library FT_Render_Glyph FT_Set_Pixel_Sizes
SDL_CloseGamepad SDL_CreateRenderer SDL_CreateSurfaceFrom SDL_CreateTexture SDL_CreateWindow
SDL_DestroyRenderer SDL_DestroySurface SDL_DestroyTexture SDL_EnableScreenSaver SDL_GetBasePath
SDL_GetClipboardText SDL_GetCurrentDisplayMode SDL_GetCurrentRenderOutputSize SDL_GetError
SDL_GetGamepadNameForID SDL_GetJoysticks SDL_GetPlatform SDL_GetPowerInfo SDL_GetPrefPath
SDL_GetPrimaryDisplay SDL_GetTouchFingers SDL_GetVersion SDL_GetWindowSize SDL_HasClipboardText
SDL_Init SDL_InitSubSystem SDL_IsGamepad SDL_OpenGamepad SDL_Quit SDL_QuitSubSystem SDL_RenderClear
SDL_RenderPresent SDL_RenderTexture SDL_SetClipboardText SDL_SetHint SDL_SetMainReady
SDL_SetRenderDrawColor SDL_SetWindowFullscreen SDL_SetWindowIcon SDL_SetWindowPosition
SDL_SetWindowTitle SDL_StartTextInput SDL_StopTextInput SDL_SyncWindow SDL_UpdateTexture
SDL_WaitEventTimeout SDL_WasInit SDL_free ZSTD_DCtx_reset ZSTD_compress ZSTD_compressBound
ZSTD_createDCtx ZSTD_decompress ZSTD_decompressDCtx ZSTD_freeDCtx ZSTD_getErrorName
ZSTD_getFrameContentSize ZSTD_isError archive_entry_filetype archive_entry_free archive_entry_new
archive_entry_pathname archive_entry_set_filetype archive_entry_set_gid archive_entry_set_mtime
archive_entry_set_pathname archive_entry_set_perm archive_entry_set_size archive_entry_set_uid
archive_entry_size archive_error_string archive_free archive_read_close archive_read_data
archive_read_data_block archive_read_disk_descend archive_read_disk_new archive_read_disk_open
archive_read_disk_set_behavior archive_read_extract2 archive_read_new archive_read_next_header2
archive_read_open_filename archive_read_support_filter_all archive_read_support_format_all
archive_write_add_filter_by_name archive_write_close archive_write_data archive_write_disk_new
archive_write_disk_set_options archive_write_header archive_write_new archive_write_open_filename
archive_write_set_format_by_name archive_write_zip_set_compression_deflate
archive_write_zip_set_compression_store bitmap2pix bmp_alloc bmp_bytewidth bmp_copy bmp_free
bmp_init boxAdjustSides boxCreate boxDestroy boxGetGeometry boxOverlapRegion boxaAddBox
boxaClipToBox boxaCombineOverlaps boxaCreate boxaDestroy boxaGetBox boxaGetBoxGeometry boxaGetCount
fz_authenticate_password fz_clear_pixmap_with_value fz_close_device fz_device_bgr fz_device_gray
fz_device_rgb fz_drop_context fz_drop_device fz_drop_document fz_drop_image fz_drop_link
fz_drop_outline fz_drop_page fz_drop_pixmap fz_drop_stext_page fz_gamma_pixmap
fz_install_external_font_funcs fz_is_document_reflowable fz_lookup_metadata fz_needs_password
fz_new_context_imp fz_new_pixmap fz_pixmap_components fz_pixmap_height fz_pixmap_samples
fz_pixmap_width fz_register_document_handlers fz_runetochar fz_scale_pixmap fz_set_user_context
fz_user_context hb_blob_create hb_blob_destroy hb_face_collect_unicodes hb_face_create
hb_face_destroy hb_face_get_glyph_count hb_ft_face_create_referenced hb_language_to_string
hb_ot_name_get_utf8 hb_ot_name_list_names hb_set_add_range hb_set_create hb_set_destroy
hb_set_get_population hb_set_intersect hb_set_set k2pdfopt_crop_bmp k2pdfopt_get_native_word_boxes
k2pdfopt_get_reflowed_word_boxes k2pdfopt_optimize_bmp k2pdfopt_reflow_bmp k2pdfopt_tocr_end
k2pdfopt_tocr_single_word lodepng_decode lodepng_decode24 lodepng_decode24_file lodepng_decode32
lodepng_decode32_file lodepng_decode_file lodepng_decode_memory lodepng_encode lodepng_encode32_file
lodepng_encode_file lodepng_error_text lodepng_inspect lodepng_state_cleanup lodepng_state_copy
lodepng_state_init mupdf_convert_pixmap mupdf_count_pages mupdf_drop_archive mupdf_drop_buffer
mupdf_drop_stream mupdf_error_code mupdf_error_message mupdf_fz_bound_page
mupdf_fz_location_from_page_number mupdf_fz_page_number_from_location mupdf_fz_pre_rotate
mupdf_fz_pre_translate mupdf_fz_rect_from_quad mupdf_fz_resolve_link mupdf_fz_round_rect
mupdf_fz_scale mupdf_fz_transform_rect mupdf_fz_translate mupdf_fz_union_rect mupdf_get_cache_size
mupdf_get_my_alloc_context mupdf_get_pixmap_from_image mupdf_layout_document mupdf_load_links
mupdf_load_outline mupdf_load_page mupdf_new_bbox_device mupdf_new_buffer_from_shared_data
mupdf_new_draw_device mupdf_new_image_from_buffer mupdf_new_pixmap_with_bbox
mupdf_new_pixmap_with_bbox_and_data mupdf_new_pixmap_with_data mupdf_new_stext_page_from_page
mupdf_open_directory mupdf_open_document mupdf_open_document_with_stream_and_dir mupdf_open_memory
mupdf_pdf_annot_contents mupdf_pdf_annot_quad_point mupdf_pdf_annot_quad_point_count
mupdf_pdf_annot_type mupdf_pdf_create_annot mupdf_pdf_delete_annot mupdf_pdf_first_annot
mupdf_pdf_next_annot mupdf_pdf_save_document mupdf_pdf_set_annot_color mupdf_pdf_set_annot_contents
mupdf_pdf_set_annot_opacity mupdf_pdf_set_annot_quad_points mupdf_run_page mupdf_search_stext_page
numaCreateFromFArray numaDestroy numaGetCount numaGetFArray numaGetIValue pixClipRectangle pixClone
pixConnCompBB pixConvertRGBToGrayFast pixConvertTo32 pixDestroy pixDrawBoxaRandom pixGetDepth
pixGetHeight pixGetRegionsBinary pixGetWidth pixInvert pixMultiplyByColor pixSplitIntoBoxa
pixThresholdToBinary pixWriteMemPng pixWritePng pixmap_to_bmp sqlite3_aggregate_context
sqlite3_bind_blob sqlite3_bind_double sqlite3_bind_int64 sqlite3_bind_null
sqlite3_bind_parameter_index sqlite3_bind_text sqlite3_busy_timeout sqlite3_clear_bindings
sqlite3_close sqlite3_close_v2 sqlite3_column_blob sqlite3_column_bytes sqlite3_column_count
sqlite3_column_double sqlite3_column_int64 sqlite3_column_name sqlite3_column_text
sqlite3_column_type sqlite3_create_function sqlite3_errmsg sqlite3_exec sqlite3_finalize
sqlite3_open_v2 sqlite3_prepare_v2 sqlite3_reset sqlite3_result_blob sqlite3_result_double
sqlite3_result_error sqlite3_result_int64 sqlite3_result_null sqlite3_result_text sqlite3_step
sqlite3_value_blob sqlite3_value_bytes sqlite3_value_double sqlite3_value_int64 sqlite3_value_text
sqlite3_value_type utf8proc_NFC utf8proc_NFKC_Casefold utf8proc_encode_char utf8proc_iterate
utf8proc_tolower utf8proc_toupper wrectmap_inside wrectmaps_free wrectmaps_init zframe_data
zframe_destroy zframe_recv zframe_send zframe_size zhash_cursor zhash_destroy zhash_unpack
zmq_getsockopt zmq_send zmsg_addmem zmsg_destroy zmsg_new zmsg_pop zmsg_popstr zmsg_send zmsg_size
zpoller_destroy zpoller_new zpoller_wait zsock_bind zsock_connect zsock_destroy zsock_new
zsock_resolve zstr_free zstr_send fz_identity fz_empty_rect fz_default_color_params luaopen_cre
luaopen_djvu luaopen_lfs luaopen_lpeg luaopen_mime_mcore luaopen_nnsvg luaopen_rapidjson
luaopen_socket_score luaopen_ssl_config luaopen_ssl_context luaopen_ssl_core luaopen_ssl_x509
luaopen_xtext
```

### 三：系统 API（74）

```text
_exit access basename calloc clock_getres clock_gettime clock_settime close dirname fclose fcntl
fdatasync feof ferror fflush fileno fopen fprintf fputc fread free freeifaddrs fstat fsync fwrite
gai_strerror getifaddrs getnameinfo getpid getpriority gettimeofday getuid htonl htons inet_aton
ioctl kill lseek lstat malloc memchr memcmp memmem memrchr memset mmap munmap nanosleep open poll
printf read realpath recv sched_yield sendto setenv setpriority sleep socket sprintf stat statvfs
strcasecmp strcmp strcoll strdup strerror strlen strndup strnlen unsetenv usleep write
```

### 四：当前未启用或不支持的路径（38）

```text
GetACP GetFullPathNameA GetSystemTimeAsFileTime MultiByteToWideChar PathFindFileNameA
PathRemoveFileSpec Sleep WideCharToMultiByte _putenv clock_nanosleep dup dup2 execl execlp execv
execvp fbink_input_check fbink_input_scan fork getppid grantpt mq_close mq_open mq_receive pipe
ptsname sched_getaffinity sched_getparam sched_getscheduler sched_setaffinity sched_setparam
sched_setscheduler setpgid setsid tcdrain tcflush unlockpt waitpid
```

第四类中 21 个 Windows/Linux/FBInk 名称在本平台不能解析；其余 17 个进程/伪终端 API 虽能取得地址，也不代表 iOS 支持对应能力。二者都不纳入启用路径门禁。

实验附加项 `SDL_PushEvent`、`ko_ios_phase_a_background_end` 均另行解析成功且被实际调用；Swift 原生调用的 `ko_ios_phase_a_install` 也由 `nm` 核对保留。剔除了初始正则把函数指针返回类型 `int` / `void` 误当符号的两条结果，没有把它们算成缺符号。
