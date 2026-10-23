# iPhone / iPad 移植：规划决策记录

grilling 记录，2026-10-23 起。依据 [可行性报告](../iOS-feasibility.md)。这里只记"决定了什么、为什么"，不是 spec；spec 和 ticket 在 grilling 结束后另发到 GitHub Issues。每轮由 owner 逐项确认。

## 待核实的前提（阶段 A 开工前补齐，不得虚构）

- owner 实际持有的 iPhone、iPad 型号与系统版本。计划基线：最低部署 iOS 17。
- 是否已有付费 Apple Developer 账号。计划基线：付费账号开发签名直接装到自有设备。

## 第一轮（Q1–Q19，2026-10-23 确认）

| # | 决定 |
| --- | --- |
| Q1 | 本轮规划承诺到"日常稳定使用"（报告阶段 A+B+C）。App Store 公开发行范围外：不预做品牌替换、不禁插件/userpatch、不做许可审计；唯一保留的约束是不采用会堵死上架路的结构（如把散放 `.dylib` 当最终打包）。稳定版的具体边界见第二轮。 |
| Q2 | 验收设备 = owner 现有的一台 iPhone 加一台 iPad，各代表一类；最低部署 iOS 17（待设备事实核实后调整）。不追求更多机型。 |
| Q3 | fork `koreader-base` 为 `justinyanme/koreader-base`，`.gitmodules` 改指 fork；iOS 补丁合入 fork 的 master，每月像 l10n 一样 merge 上游，补丁尽量只增文件。见 [ADR-0007](../adr/0007-forked-base-submodule-for-ios.md)。 |
| Q4 | 技术验证（阶段 A）在仓库外独立目录 clone hezi 并 pin 到 `a7cf2a98` / `6e4bafc0`，作为父 issue 下第一张 ticket，有退出条件；结论写回 `doc/ios/`。阶段 A 没过关，后续 ticket 不开工。 |
| Q5 | iOS 沿用墨水屏改版的界面语法（分页、无动画、黑白灰 chrome），参考基准仍是微信读书墨水屏版 Leaf5 实机。按手机版重做是另一个产品决定，不进本轮。见 [ADR-0008](../adr/0008-ios-keeps-eink-ui-grammar.md)。 |
| Q6 | 界面 chrome 保持黑白灰；书的内容（插图、PDF 页、封面原图）按引擎输出彩色显示，不量化成 16 灰。夜间模式仍是整屏反色，不跟随系统深色模式。 |
| Q7 | iOS 设备把 dp 标尺设为 1dp≈1pt；iPhone 成为新的"窄屏"等级（约 390dp 宽），按比例规则重算，只为放不下的组件补规则。具体倍率真机验证后定。见 ADR-0008。 |
| Q8 | iOS 作为 `frontend/device/sdl/device.lua` 里与 Desktop、Emulator 并列的变体，由 SDL 平台名选中；能力位初值：`isSDL=yes`、`isDesktop=no`、`isEmulator=no`、`hasEinkScreen=no`、`hasFrontlight=yes`（系统亮度）、`hasNaturalLight=no`、`hasKeys/hasDPad/hasKeyboard=no`、`hasWifiToggle=no`、`hasOTAUpdates=no`、`canRestart/hasExitOptions=no`、`isDefaultFullscreen=yes`、`hasSystemFonts=yes`；新增通用能力位 `isIOS`，默认 `no`。硬规则：改版模块只按能力位分支，`isIOS` 只允许出现在设备层和原生桥。墨水屏零回归是**门禁要验证的目标**（Docker 全量 + Leaf5 验收），不是保证。 |
| Q9 | 墨水屏专属入口按能力位隐藏、不留占位：`hasEinkScreen=no` 隐藏刷新与残影；`hasNaturalLight=no` 隐藏色温；`hasOTAUpdates=no` 隐藏"我"页版本更新。若现有入口尚未按能力位判断，补判断算 iOS ticket 的一部分，Leaf5 行为不变。 |
| Q10 | 书在 `Documents`（主目录），设置和笔记数据在 `Library/Application Support`，可重建缓存在 `Library/Caches`；`.sdr` 集中存放（`document_metadata_folder = "dir"`）。导入三条路都做、都是复制进主目录：Files 里露出 `Documents`；导入页"设备文件"换成系统文件选择器；注册文档类型支持"用 KOReader 打开"。不做授权目录原地阅读。 |
| Q11 | 书源进首个可用版本，修正报告的阶段划分；下载的异步实现在阶段 B 解决。 |
| Q12 | 三处 fork 调用按任务各自替换，不做通用任务框架：书源下载走原生 URLSession 桥（Lua 轮询 start/poll/cancel，短时后台任务只收尾）；封面提取进程内、每 tick 一本；后台重排和缩略图子进程在 iOS 上关闭（能力位门）。原生桥总原则：C ABI 函数 + Lua 轮询，无 FFI callback、无第二个 Lua VM。见 [ADR-0009](../adr/0009-ios-native-bridge-polling-only.md)。 |
| Q13 | 首版原生桥清单：生命周期、安全区、亮度、打开 URL、文件选择器、分享面板，加 SDL 自带键盘与文本输入。VoiceOver、外接键盘/指针、Keychain 不在首版；它们落在哪个阶段，以及可访问性与凭据保护的最小范围，见第二轮。 |
| Q14 | 保存三层：笔记和进度变更后几秒内合并落盘；收到失活/进后台事件时在同一次处理里调用 `UIManager:flushSettings()` 和 `ReaderUI:saveSettings()`；内存警告时释放可重建缓存。验收按报告第 8 节"切后台、锁屏、被回收、升级安装不丢数据"。 |
| Q15 | 首版两类设备都 `UIRequiresFullScreen`，不做分屏、多窗口；横竖屏都支持，沿用 SDL 窗口尺寸变化路径和 DESIGN.md 的旋转重排规则。iPad 分屏归属阶段见第二轮。 |
| Q16 | 首版查询入口按能力位隐藏（不画假按钮）；版式书只做渲染、缩放、裁切，重排隐藏。sdcv 进程内化和重排的归属阶段见第二轮。 |
| Q17 | 付费账号开发签名直接装到两台设备，不用 TestFlight；Bundle ID 用 owner 自己的域名反写，显示名 KOReader。（账号事实待核实。） |
| Q18 | 共享 Lua 改动照旧过 Docker 全量；iOS 设备变体的纯 Lua 部分在 Docker 里通过伪造 SDL 平台名写 spec；原生桥和真机行为用 `doc/ios/` 下的手工验收清单在两台设备上过；首版不建 iOS CI 和模拟器构建。动了共享模块，Leaf5 验收照旧。 |
| Q19 | 墨水屏仍是主目标，iPhone/iPad 作为第二类屏幕加入文档：CONTEXT.md 加定位句和"窄屏"词条；PRODUCT.md 加 iOS 使用环境小节；DESIGN.md 把面板下限扩到窄屏并记录 Q6 彩色内容规则（后两项在 spec 阶段随对应 ticket 更新）。 |

## 只能真机验证、不是决策

Release 下 FFI 导出符号是否被裁剪；解释器模式下大 EPUB 打开、翻页、划线耗时；`/System/Library/Fonts` 下中文字体能否被 crengine 读到；锁定 SDL 版本的 scene 生命周期事件是否送达 Lua；KOPT 重排不可用是构建问题还是能力问题；Q7 的具体 DPI 倍率。
