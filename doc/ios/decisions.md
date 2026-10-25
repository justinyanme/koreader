# iPhone / iPad 移植：规划决策记录

grilling 记录，2026-10-23 起。依据 [可行性报告](../iOS-feasibility.md)。这里只记"决定了什么、为什么"，不是 spec；spec 和 ticket 在 grilling 结束后另发到 GitHub Issues。每轮由 owner 逐项确认。后一轮与前一轮冲突时以后一轮为准，被覆盖的条目末尾标"→ Qn"。

## 已核实的前提（2026-10-25，本机 `devicectl` 与钥匙串）

- iPhone 17 Pro Max（`iPhone18,2`），iOS 27.0.1；iPad Pro 11 英寸 M5（`iPad17,1`），iOS 27.0。
- 有付费 Apple Developer 账号，Team `V88UWDRASU`，本机已有 Apple Development 证书。
- 性能样书《蘋果之道》在 owner 的 iCloud Drive。
- 本机有 Xcode 27.1（`xcode-select` 默认指向 26.6，iOS 构建用 `DEVELOPER_DIR` 指定 27.1），Tuist 4.155.3。iOS 27 模拟器运行时还没装。

## 第一轮（Q1–Q19，2026-10-23 确认）

| # | 决定 |
| --- | --- |
| Q1 | 本轮规划承诺到"日常稳定使用"（报告阶段 A+B+C）。App Store 公开发行范围外：不预做品牌替换、不禁插件/userpatch、不做许可审计；唯一保留的约束是不采用会堵死上架路的结构（如把散放 `.dylib` 当最终打包）。稳定版的具体边界见第二轮。→ Q43、Q44 |
| Q2 | 验收设备 = owner 现有的一台 iPhone 加一台 iPad，各代表一类；最低部署 iOS 17（待设备事实核实后调整）。不追求更多机型。→ Q42 |
| Q3 | fork `koreader-base` 为 `justinyanme/koreader-base`，`.gitmodules` 改指 fork；iOS 补丁合入 fork 的 master，每月像 l10n 一样 merge 上游，补丁尽量只增文件。见 [ADR-0007](../adr/0007-forked-base-submodule-for-ios.md)。 |
| Q4 | 技术验证（阶段 A）在仓库外独立目录 clone hezi 并 pin 到 `a7cf2a98` / `6e4bafc0`，作为父 issue 下第一张 ticket，有退出条件；结论写回 `doc/ios/`。阶段 A 没过关，后续 ticket 不开工。 |
| Q5 | iOS 沿用墨水屏改版的界面语法（分页、无动画、黑白灰 chrome），参考基准仍是微信读书墨水屏版 Leaf5 实机。按手机版重做是另一个产品决定，不进本轮。见 [ADR-0008](../adr/0008-ios-keeps-eink-ui-grammar.md)。 |
| Q6 | 界面 chrome 保持黑白灰；书的内容（插图、PDF 页、封面原图）按引擎输出彩色显示，不量化成 16 灰。夜间模式仍是整屏反色，不跟随系统深色模式。 |
| Q7 | iOS 设备把 dp 标尺设为 1dp≈1pt；iPhone 成为新的"窄屏"等级（约 390dp 宽），按比例规则重算，只为放不下的组件补规则。具体倍率真机验证后定。见 ADR-0008。→ Q42 |
| Q8 | iOS 作为 `frontend/device/sdl/device.lua` 里与 Desktop、Emulator 并列的变体，由 SDL 平台名选中；能力位初值：`isSDL=yes`、`isDesktop=no`、`isEmulator=no`、`hasEinkScreen=no`、`hasFrontlight=yes`（系统亮度）、`hasNaturalLight=no`、`hasKeys/hasDPad/hasKeyboard=no`、`hasWifiToggle=no`、`hasOTAUpdates=no`、`canRestart/hasExitOptions=no`、`isDefaultFullscreen=yes`、`hasSystemFonts=yes`；新增通用能力位 `isIOS`，默认 `no`。硬规则：改版模块只按能力位分支，`isIOS` 只允许出现在设备层和原生桥。墨水屏零回归是**门禁要验证的目标**（Docker 全量 + Leaf5 验收），不是保证。 |
| Q9 | 墨水屏专属入口按能力位隐藏、不留占位：`hasEinkScreen=no` 隐藏刷新与残影；`hasNaturalLight=no` 隐藏色温；`hasOTAUpdates=no` 隐藏"我"页版本更新。若现有入口尚未按能力位判断，补判断算 iOS ticket 的一部分，Leaf5 行为不变。→ Q49 |
| Q10 | 书在 `Documents`（主目录），设置和笔记数据在 `Library/Application Support`，可重建缓存在 `Library/Caches`；`.sdr` 集中存放（`document_metadata_folder = "dir"`）。导入三条路都做、都是复制进主目录：Files 里露出 `Documents`；导入页"设备文件"换成系统文件选择器；注册文档类型支持"用 KOReader 打开"。不做授权目录原地阅读。→ Q43 |
| Q11 | 书源进首个可用版本，修正报告的阶段划分；下载的异步实现在阶段 B 解决。 |
| Q12 | 三处 fork 调用按任务各自替换，不做通用任务框架：书源下载走原生 URLSession 桥（Lua 轮询 start/poll/cancel，短时后台任务只收尾）；封面提取进程内、每 tick 一本；后台重排和缩略图子进程在 iOS 上关闭（能力位门）。原生桥总原则：C ABI 函数 + Lua 轮询，无 FFI callback、无第二个 Lua VM。见 [ADR-0009](../adr/0009-ios-native-bridge-polling-only.md)。 |
| Q13 | 首版原生桥清单：生命周期、安全区、亮度、打开 URL、文件选择器、分享面板，加 SDL 自带键盘与文本输入。VoiceOver、外接键盘/指针、Keychain 不在首版；它们落在哪个阶段，以及可访问性与凭据保护的最小范围，见第二轮。 |
| Q14 | 保存三层：笔记和进度变更后几秒内合并落盘；收到失活/进后台事件时在同一次处理里调用 `UIManager:flushSettings()` 和 `ReaderUI:saveSettings()`；内存警告时释放可重建缓存。验收按报告第 8 节"切后台、锁屏、被回收、升级安装不丢数据"。 |
| Q15 | 首版两类设备都 `UIRequiresFullScreen`，不做分屏、多窗口；横竖屏都支持，沿用 SDL 窗口尺寸变化路径和 DESIGN.md 的旋转重排规则。iPad 分屏归属阶段见第二轮。 |
| Q16 | 首版查询入口按能力位隐藏（不画假按钮）；版式书只做渲染、缩放、裁切，重排隐藏。sdcv 进程内化和重排的归属阶段见第二轮。→ Q52 |
| Q17 | 付费账号开发签名直接装到两台设备，不用 TestFlight；Bundle ID 用 owner 自己的域名反写，显示名 KOReader。（账号事实待核实。）→ Q43 |
| Q18 | 共享 Lua 改动照旧过 Docker 全量；iOS 设备变体的纯 Lua 部分在 Docker 里通过伪造 SDL 平台名写 spec；原生桥和真机行为用 `doc/ios/` 下的手工验收清单在两台设备上过；首版不建 iOS CI 和模拟器构建。动了共享模块，Leaf5 验收照旧。→ Q42 |
| Q19 | 墨水屏仍是主目标，iPhone/iPad 作为第二类屏幕加入文档：CONTEXT.md 加定位句和"窄屏"词条；PRODUCT.md 加 iOS 使用环境小节；DESIGN.md 把面板下限扩到窄屏并记录 Q6 彩色内容规则（后两项在 spec 阶段随对应 ticket 更新）。 |

## 要实测、不是决策

模拟器能定：Release 下 FFI 导出符号是否被裁剪；`/System/Library/Fonts` 下中文字体能否被 crengine 读到；锁定 SDL 版本的 scene 生命周期事件是否送达 Lua；KOPT 重排不可用是构建问题还是能力问题；Q7 的具体 DPI 倍率（模拟器的 point 和 scale 与同型号真机一致）。

模拟器先测、真机复核（Q42）：解释器模式下大 EPUB 打开、翻页、划线耗时；峰值内存。只能真机：耗电、系统亮度实际变化、VoiceOver 朗读、来电打断、系统真实的内存回收、Finder 文件共享。

## 第二轮（Q20–Q32，2026-10-23 确认）

| # | 决定 |
| --- | --- |
| Q20 | 阶段边界：**首版**＝书架、阅读、目录页、笔记页、排版/进度面板、笔记三类、书源浏览与异步下载、三条复制式导入、生命周期保存、安全区、亮度、打开 URL、分享、横竖屏全屏。**稳定版**（Q1 承诺终点）＝查询进程内化（sdcv 库或 Lua 读 StarDict）、VoiceOver 最小闭环、凭据进 Keychain、外接键盘翻页；KOPT 重排只在阶段 A 证明是构建问题时进稳定版，否则后续。**后续（本轮不承诺）**＝iPad 分屏、多窗口、Pencil、授权目录原地阅读、后台长下载、模拟器 CI、指针悬停、其余页面的 VoiceOver。首版里查询和重排入口按能力位隐藏，不画假按钮。→ Q52 |
| Q21 | 可访问性最小范围：首版靠 44pt 触控目标、R05 五档界面字号、原生键盘/文件选择器/分享面板。稳定版 VoiceOver 只覆盖五个流程：书架选书打开、翻页、呼出工具栏进四个入口、返回书架、目录页选章；Lua 声明可访问区域，原生用 `UIAccessibilityElement` 覆盖层暴露，仍走轮询原则。 |
| Q22 | 凭据保护最小范围：首版不加桥，依赖 iOS 默认文件保护，并检查书源和 KOSync 不把凭据写日志；备份排除的边界见第三轮。稳定版加 get/set/delete 三函数 Keychain 桥，书源 Basic 密码、Service Token、KOSync 密码迁入，设置文件只留引用；原版 OPDS 浏览器不动。 |
| Q23 | 阶段 A go/no-go 是**我们选定的验收目标**，不是任何实测：两台设备 Release 独立启动且 30 分钟阅读不崩溃；中文长 EPUB 冷打开 ≤ 10 s、二次 ≤ 3 s、30 次翻页中位数 ≤ 500 ms；切后台再回来进度和划线不丢；声明的 FFI 符号全部可解析（范围见第三轮）。任一不达标停下评估。样书、设备、账号可用性实施前核实。→ Q42 |
| Q24 | `platform/ios/`（启动器、`Info.plist.in`、xcodegen `project.yml`、图标），生成的 `.xcodeproj` 不入库；`make/ios.mk`；`./kodev build ios`、`./kodev run ios`（打开 Xcode 工程）；验证记录和手工验收清单在 `doc/ios/`。→ Q40、Q41 |
| Q25 | 隐藏 iOS 状态栏；可用区域＝安全区（`Device.viewport`），底色填满整屏；时间电量由 KOReader 自己的状态栏和页脚显示；安全区变化和窗口尺寸变化走同一条重排路径。 |
| Q26 | 原生 SDL 事件 watcher 在失活/进后台时只申请后台续时并让事件入队；Lua 主循环优先处理并同步保存，保存完结束续时；配合秒级合并落盘。续时失败、过期和写入中断的处理见第三轮，记入 ADR-0009 后果。 |
| Q27 | 静态链接加显式导出列表，构建时用 `nm` 核对，缺则失败；核对范围分类见第三轮。 |
| Q28 | 下载桥：`start(url, headers, dest_tmp)`→句柄；`poll`→状态、已收/总字节、HTTP 状态码、错误文本；`cancel`。临时文件由 Lua 原子移动或清理；并发上限沿用现有书源代码；离开书源页取消全部（ADR-0005）；同源敏感头策略留在 Lua（ADR-0004），重定向处理见第三轮。 |
| Q29 | 窄屏规则采集：未来 ticket 的交付物，在 Docker 离屏以 390×844 和 820×1180 截出十个页面，标出溢出、截断、触控目标不足的组件，形成规则清单再进 spec。写 spec 不以此为前提。 |
| Q30 | "文件"页只浏览沙盒 `Documents`，没有别的根；导入页"从电脑传书"文案改成 Files 的"我的 iPhone/KOReader"和 Finder 文件共享。→ Q43 |
| Q31 | 随包插件：以 `make/android.mk` 排除清单为起点，再排除执行外部二进制/shell 的和墨水屏专属的；保留统计、KOSync、Calibre 无线、云存储、OPDS、封面浏览、自动翻页、生词本、词典（稳定版启用）。在构建配置里定。 |
| Q32 | 没有显式 `language` 设置时跟随系统首选语言（`SDL_GetPreferredLocales`，不加桥）；原版入口可覆盖。 |

## 第三轮（Q33–Q39，2026-10-23 确认；frontier 为空）

| # | 决定 |
| --- | --- |
| Q33 | 首版不做任何备份排除：数据目录（含设置、docsettings、笔记）整体随 iCloud/Finder 备份，凭据暂以明文存在备份里。iCloud 备份由 Apple 加密；**Finder 备份是否加密取决于用户设置**，不能假定。稳定版迁入 Keychain 时用 AfterFirstUnlockThisDeviceOnly，恢复到新设备后书源和 KOSync 需重新登录，笔记和进度照常恢复。永远不排除数据目录；若将来排除单个凭据文件，必须同时提供重新登录路径。 |
| Q34 | 下载桥不自动跟随重定向，把 3xx 和 Location 交给 Lua；复用 `opdsclient` 已有的跳转循环（次数上限、拒绝 https 降级、`auth_headers` 只发同源，每一跳重判）。书源的下载路径必须改为走同一个策略函数，不允许第二套判断。验收：跨域 302 后敏感头不出现在第二个请求里。 |
| Q35 | 符号核对分四类：`ko_ios_*` 桥符号和 `platform/ios/ffi-symbols.txt` 列出的静态 base 库符号在构建时用 `nm` 核对、缺则失败；系统库符号由 dyld 解析、只在 Debug 启动自检里 `pcall` 解析并记日志；按能力未启用路径的 cdef（mxcfb、Android JNI、inotify、sdcv popen 等）不在清单。清单随 iOS 模块集维护，不自动扫全部 cdef。 |
| Q36 | 后台保存六条：从 `willResignActive` 开始保存；续时标识无效时照常保存；过期回调立即结束任务并置标志，Lua 先写进度、笔记、设置三样必要项，过期后跳过非必要项；写入原子性依赖 `LuaSettings` 现有的临时文件 + fsync + 改名 + `.old`（`.sdr` 同类；阶段 A 验证在 iOS 上成立） → Q47；回前台时检查"保存未完成"标志补做；秒级合并落盘。**秒级落盘是正常可调度时的目标**，不保证崩溃、主循环阻塞或存储失败时只丢几秒；这些情形的验收是"已落盘的数据不损坏、可恢复到上一个完整版本"。 |
| Q37 | ticket 切分：T0 阶段 A 技术验证（仓库外，交付 `doc/ios/phase-a-report.md`）；B0 窄屏离屏采集（Docker，与 T0 并行，只阻塞 B4）；B1 base fork 与构建骨架、符号门禁；B2 iOS 设备变体与能力位隐藏；B3 存储布局与三条导入；B4 dp 标尺、安全区、旋转、窄屏规则并更新 DESIGN/PRODUCT；B5 生命周期保存；B6 下载桥与书源；B7 封面进程内、后台重排与缩略图关闭；B8 亮度、URL、分享、语言、插件清单；C1 查询进程内化；C2 Keychain；C3 VoiceOver 五流程；C4 外接键盘；C5 KOPT（条件触发）；C6 手工验收清单 `doc/ios/acceptance.md` 与性能、内存、耗电记录；C7 Leaf5/Android 回归。阻塞：T0 → B1 → B2 → {B3, B4, B5} → {B6, B7, B8} → C1–C5 → C6 → C7。 |
| Q38 | 一个父 issue；ticket 一次建好并带 Blocked by，创建时只给 T0 和 B0 打 `ready-for-agent`，T0 报告通过后再逐级打标。 |
| Q39 | PRODUCT.md 和 DESIGN.md 由 B4 一并修改：Users、Operating Context、Capabilities、Accessibility 各加 iOS 内容；DESIGN 的 Layout 加窄屏 390 和 iPad 约 820 两档并写明 1dp≈1pt，Colors 加内容彩色规则，Refresh mapping 注明 LCD 上无效果但声明保留。design/demo 不改。 |

## to-spec 与 to-tickets（2026-10-23）

父 issue：[#85 feat(ios): 把微信读书式 KOReader 改版移植到 iPhone 和 iPad](https://github.com/justinyanme/koreader/issues/85)。测试接缝 A（ReaderUI）、B（书架/FileManager）沿用既有，C（iOS 设备变体构造点，可注入 SDL 平台名与原生桥函数表）是唯一新增。

### 18 张 ticket 与真实阻塞边

对首轮 Q37 的切分做了三处调整：新增 P1 预重构（书源下载统一走 opdsclient 策略，是 B6 前置，也修 ADR-0004 在下载路径上的缺口）；B8 瘦身为三座桥，语言并入 B2、插件清单并入 B1；阻塞边收紧为真实依赖（B5/B6/B7/C1 只等 B3，B8/C4 只等 B2，C2 等 B6，C3 等 B4，C5 等 B1）。子 issue 的 Blocked by 优先于 #85 Further Notes 的粗略顺序。全部为 #85 的原生 sub-issue，依赖用原生 blocked_by。

| 票 | issue | Blocked by |
| --- | --- | --- |
| T0 阶段 A 技术验证 | [#86](https://github.com/justinyanme/koreader/issues/86) | 无 |
| B0 窄屏离屏采集 | [#87](https://github.com/justinyanme/koreader/issues/87) | 无 |
| P1 书源下载统一走 opdsclient 策略 | [#88](https://github.com/justinyanme/koreader/issues/88) | 无 |
| B1 iOS 构建骨架 | [#89](https://github.com/justinyanme/koreader/issues/89) | #86 |
| B2 iOS 设备变体与能力位 | [#90](https://github.com/justinyanme/koreader/issues/90) | #89 |
| B3 沙盒内的书与数据 | [#91](https://github.com/justinyanme/koreader/issues/91) | #90 |
| B4 dp 标尺、安全区与窄屏规则 | [#92](https://github.com/justinyanme/koreader/issues/92) | #90、#87 |
| B5 生命周期保存 | [#93](https://github.com/justinyanme/koreader/issues/93) | #91 |
| B6 书源异步下载 | [#94](https://github.com/justinyanme/koreader/issues/94) | #91、#88 |
| B7 书架封面与无 fork 任务 | [#95](https://github.com/justinyanme/koreader/issues/95) | #91 |
| B8 亮度、打开链接、分享 | [#96](https://github.com/justinyanme/koreader/issues/96) | #90 |
| C1 查询进程内化 | [#97](https://github.com/justinyanme/koreader/issues/97) | #91 |
| C2 Keychain | [#98](https://github.com/justinyanme/koreader/issues/98) | #94 |
| C3 VoiceOver 五流程 | [#99](https://github.com/justinyanme/koreader/issues/99) | #92 |
| C4 外接键盘翻页 | [#100](https://github.com/justinyanme/koreader/issues/100) | #90 |
| C5 KOPT 重排（条件票） | [#101](https://github.com/justinyanme/koreader/issues/101) | #89 |
| C6 稳定版综合验收 | [#102](https://github.com/justinyanme/koreader/issues/102) | #92–#101 |
| C7 Leaf5 与 Android 回归 | [#103](https://github.com/justinyanme/koreader/issues/103) | #102 |

### 打标规则（更新 Q38）

创建时只给 **T0、B0、P1** 打 `ready-for-agent`（P1 的依赖已满足，owner 在 to-tickets 阶段明确把它加入可开工前沿，取代先前"只 T0、B0"的规则）。其余票在其 blocked_by 全部关闭后再打标。T0 结论为 no-go 时，B1 及其下游不解锁。

## 第四轮（Q40–Q44，2026-10-25 owner 指定）

| # | 决定 |
| --- | --- |
| Q40 | Xcode 工程由 Tuist 管理：`platform/ios/` 放 Tuist 清单（Info.plist 的键写在清单里，不再有 `Info.plist.in`）、Swift 源码和图标；Tuist 版本用仓库根的 `mise.toml` 固定；生成的 `.xcodeproj`/`.xcworkspace` 不入库。`./kodev build ios` 依次构建 base 的 iOS 静态库、`tuist generate`、`xcodebuild`，默认产出模拟器包，加参数产出真机包；`./kodev run ios` 把包装进模拟器并启动。覆盖 Q24 的 xcodegen 和"打开 Xcode 工程"。见 [ADR-0010](../adr/0010-ios-native-layer-swift-uikit-tuist.md)。 |
| Q41 | 原生层（启动器、`ko_ios_*` 桥）用 Swift 写，只用 UIKit 和 Foundation，不用 SwiftUI，不新写 Objective-C；桥用 Swift 的 `@c` 导出 C ABI，ADR-0009 的轮询原则不变。hezi 的 Objective-C 只作参考。C/C++ 只留在 koreader-base 的引擎和库里。见 ADR-0010。 |
| Q42 | 代理开发、调试、ticket 验收都在模拟器上做：Xcode 27.1，iOS 27 运行时，iPhone 17 Pro Max 和 iPad Pro 11 英寸（M5）两台模拟器，对应 owner 的真机。base 的 iOS 构建要同时支持 `iphonesimulator` 和 `iphoneos` 两种 arm64（hezi 只做了后者）。最低部署版本改为 iOS 27。真机由 owner 在想体验时自己装，需要的步骤写进 `doc/ios/acceptance.md` 的"真机复核"一节，建议首版 B1–B8 关闭后跑第一次；C6 是稳定版的完整一轮。T0 的 go/no-go 按 Q23 的目标值在模拟器上判定，性能数值算临时门禁，真机复核不达标时同样停下评估。仍不建 iOS CI。覆盖 Q2 的部署版本、Q7 的"真机验证"、Q18 的"不建模拟器构建"、Q23 的"两台设备"。 |
| Q43 | App 名 **Just Reader**，Bundle ID `me.justinyan.justreader`，Team `V88UWDRASU` 开发签名。Files 里显示为"我的 iPhone/Just Reader"，分享菜单里显示为"用 Just Reader 打开"。App 内文案（关于页、致谢）里的 KOReader 字样本轮不改。覆盖 Q17 的显示名和"域名待定"，以及 Q10、Q30 里的文案。 |
| Q44 | 第一版完全免费：不接 StoreKit，不做内购、订阅或付费功能，也不为收费预留结构。 |

## 第五轮（Q45–Q46，2026-10-25 owner 指定）

| # | 决定 |
| --- | --- |
| Q45 | 发布通道照搬 justoodoo（`docs/agents/delivery.md`）：fastlane + match（与 justoodoo、Just-ABC 共用证书仓库和证书）+ mise 任务。`ios:tf` 上传 TestFlight，Internal 组自动拿到，同时提交 Beta App Review 进 External 组；`ios:ota` 发布开发签名包到 `https://test.justinyan.app/justreader/`。新增 D0 票：先做一个空壳 App 上 TestFlight，让 Apple 的审核尽早开始。空壳只在 `platform/ios/` 下，不碰 Lua 代码，不等 T0；T0 判 no-go 时整个目录撤掉。B1 在 D0 的工程上扩展。不用 GitHub Actions，确有需要时用本机做 runner。覆盖 Q17 的"不用 TestFlight"和 Q4 里"没过关不合主线"对这个目录的约束。 |
| Q46 | 每张票照常写 spec，但实现过程中不跑测试（单个 spec 和全量都不跑），也不逐票做 Leaf5 实机验收；每次提交 TestFlight 之前，由编排者批量跑全量并修复。各票验收里"跑 Docker 全量""Leaf5 实机验收"两条按此执行。iOS 构建和模拟器冒烟不算测试，照做。 |

## 更正（Q47，2026-10-25）

| # | 决定 |
| --- | --- |
| Q47 | Q36 和 ADR-0009 说"`LuaSettings` 现有写法是临时文件 + fsync + 改名 + `.old`"是错的。T0 核对发现：`LuaSettings:flush` 和 `.sdr` 的写入都是原地 `io.open("wb")` 加 fsync，只有文件超过 60 秒未改时才先改名为 `.old`。B5（#93）因此要把两者改为写临时文件、fsync、改名替换，并保留 `.old`。这是共享代码改动，墨水屏同样受益，按 Q46 统一回归。缺少原子写入本身不判 T0 no-go；T0 用未修改的代码实测时，如果出现数据丢失或文件损坏，仍按规则判 no-go。 |

## 门禁口径（Q48，2026-10-25，编排者依 owner 授权裁定）

| # | 决定 |
| --- | --- |
| Q48 | T0 的"切后台再回来进度和划线不丢"一项，判定对象是 ADR-0009 的保存设计，而不是 hezi 原样移植。hezi 移植没有进后台保存这一层，原样跑必然丢数据，这正是 B5 要补的。T0 照实记录原样移植的失败，然后在仓库外的副本里按 ADR-0009 做最小 B5 原型（续时加事件入队，Lua 同步 flushSettings 和 saveSettings），用同样步骤重跑。生命周期事件能送达 Lua，且原型在两台模拟器上都不丢数据，这一项才判 go；否则判 no-go。其他门禁项不变。 |

## 版本说明更正（Q49，2026-10-25，编排者依 owner 授权裁定）

| # | 决定 |
| --- | --- |
| Q49 | 更正 Q9："我"页的"版本更新"自 #64 起只显示当前版本，点开是 About 和安装说明，从不检查或执行 OTA，因此不按 `hasOTAUpdates` 隐藏。Leaf5、Emulator 保持现有版本行和 APK 说明；iOS 同样保留版本行，由设备提供安装说明，显示"更新请在 TestFlight 中安装新版本。"（英文 gettext 原文为 `To update it, install the new build from TestFlight.`）。原版菜单的 OTA 入口仍按 `hasOTAUpdates` 判断。刷新、残影与色温的能力位规则不变。 |

## 实施中的补充（Q50–Q51，2026-10-25，编排者依 owner 授权）

| # | 决定 |
| --- | --- |
| Q50 | Q12 列出的 fork 调用点漏了两处，补进对应的票：书源封面缩略图 `booksourceview:fetchThumbs` 归 B6（#94），no-fork 时走同一个下载桥和同一组 hop/follow 策略，否则 iOS 上书源网格是空白的；"文件"页的移动、复制（`/bin/mv`、`/bin/cp`）以及"执行脚本"入口另开 C8（#144）。 |
| Q51 | B0 的 P6（新打开的书在选边距之前不受 38 字上限约束）在墨水屏横屏上同样存在，修它会改变墨水屏行为，B4 不做，留给 owner 决定是否另开票。B4 的其他 iPad 观察项（P1–P5）以 Emulator 竖屏和横屏渲染逐像素不变为前提处理。 |

## C5 结论（Q52，2026-10-25，编排者依 owner 授权）

| # | 决定 |
| --- | --- |
| Q52 | 更正 Q16、Q20 里"重排入口隐藏"：T0 判定 KOPT 不可用是构建问题，C5（#101）走构建路径。B1 已静态链接 k2pdfopt 和 leptonica，版式书底栏的"Reflow"开关在 iOS 上照常显示，不加能力位。翻页模式的后台预重排用线程而不是子进程，iOS 上照常开启；iOS shim 把 `ffi.load("pthread")` 解析到 `ffi.C`（libSystem）。滚动模式翻页受 DocCache 只有 16MB 拖慢，归 C9（#150）。 |
