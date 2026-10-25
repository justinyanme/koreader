# iOS 手工验收清单

本清单依据 [#86](https://github.com/justinyanme/koreader/issues/86)、[决策记录](decisions.md) Q23、Q35、Q36、Q42、Q46–Q48 和 [ADR-0010](../adr/0010-ios-native-layer-swift-uikit-tuist.md)。阶段 A 的实测结果、构建补丁和 go/no-go 以 [phase-a-report.md](phase-a-report.md) 为准。本文件是可复用的空白骨架，勾选状态不代表本票实测结果。

## 模拟器

### 记录与准备

- [ ] 记录日期、顶层/base 完整 SHA、实验补丁、构建配置、工具版本、App Bundle ID、宿主机芯片/内存/macOS、设备型号、运行时版本和 build。
- [ ] 固定 iPhone 17 Pro Max 与 iPad Pro 11 英寸（M5）两台独立模拟器；性能在 iOS 27.x 上测。阶段 A 使用 Xcode 27.1 SDK、部署版本 27.0、iOS 27.0 `24A434`；已安装的 27.1 `24A94425` 仅支持 iPhone Duo，不能用于这两台机型。
- [ ] 从干净 clone 复现 arm64 `iphonesimulator` Release，核对 Mach-O 的平台，使用 `simctl install` / `simctl launch`，不附加调试器。实验仅在仓库外；不要把 hezi 的一次性工程和样书提交进主仓库。
- [ ] 对《蘋果之道》原文件只读复制，核对 SHA-256、文件大小；iCloud 占位文件先完成下载。记录冷打开的缓存清理范围。
- [ ] 区分基线 Release、计时/翻页驱动 Release、符号审计 Release；说明埋点、计时边界和采样方法。驱动不得替 App 保存进度或笔记。

### 阶段 A 门禁：两台各执行一遍

| 项目 | 操作与记录 | 目标 |
| --- | --- | --- |
| 独立启动 | Release 不挂调试器，确认进入可操作的阅读画面 | 成功 |
| 冷打开 | 清空 App 的书籍排版/字体/文档缓存及书籍设置后打开样书；记录从启动请求至首个书籍画面的耗时，同时记录书籍打开内部耗时 | ≤ 10 s |
| 第二次打开 | 保留已有数据，记录再次打开同一本书的方式和耗时 | ≤ 3 s |
| 翻页 | 完成 30 次实际分页并渲染，保存逐次样本、中位数和最慢样本；说明端点是否是 SDL 提交画面 | 中位数 ≤ 500 ms |
| 连续阅读 | 同一次进程会话持续 ≥ 30 分钟；脚本须注入 SDL 输入，确认 `InputEvent` 和持续清醒，记录起止时间、翻页数、进程状态及异常日志 | 不崩溃、不进入模拟休眠 |
| 后台恢复 | 在中文正文添加划线、改变进度，记录页码与 xpointer、划线文本/范围/数量；切后台再恢复，核对画面与内存状态 | 进度与划线不丢 |
| 锁屏恢复 | 再改变进度并添加划线，锁屏、唤醒，核对同一组数据 | 进度与划线不丢 |
| 后台终止恢复 | 再添加一条可辨识划线并改变进度；切后台约 5 秒后执行 `xcrun simctl terminate <UDID> <BundleID>`，重新启动；核对磁盘 `.sdr` 与实际恢复画面 | 进度与划线不丢，文件未损坏 |
| FFI | 按下面四类维护有效模块的清单；核对最终 Release 的 `nm` 与运行时解析结果，记录任何缺失 | 启用路径声明的桥/base 符号全部可解析 |

- [ ] iPhone：逐项填写目标、实测、通过/失败、证据位置。
- [ ] iPad：逐项填写目标、实测、通过/失败、证据位置。
- [ ] Q48：先记录原样 hezi 的失败，再在仓库外验证 B5 设计原型。原生只申请续时与入队；Lua 主循环同步 `flushSettings()` / 当前 ReaderUI `saveSettings()`，之后结束续时，不靠驱动保存、不改原子写入。事件送达且两台三种流程都不丢数据才通过；正式 B5 另按完整设计复验。
- [ ] 任一门禁失败即记录 **no-go**，列出根因、阻塞项及复验条件；不降低目标，不据此解锁 B1 及其下游。

### 技术未知数与限时探针

- [ ] Q35 类一：列出 `ko_ios_*`，验证 C ABI、可见性、显式保留/导出及 `ffi.C` 解析；不能用 Debug 成功代替 Release。
- [ ] Q35 类二：按实际启用的 base 模块维护静态库函数清单雏形；B1 将其落实为 `platform/ios/ffi-symbols.txt` 和缺符号即失败的构建门禁。
- [ ] Q35 类三：单列由 dyld 解析的系统库函数。发行实现按 Q35 在 Debug 自检；T0 的审计结果须注明构建类型。
- [ ] Q35 类四：单列能力关闭的 cdef，例如墨水屏 ioctl、Android JNI、inotify、外部 sdcv/fork 路径；不把全仓 cdef 扫描结果当作 iOS 发行清单。
- [ ] 最小 Swift `@c` 探针：Release 静态链接 LuaJIT 与至少一个 base 库，保留 Swift C ABI 符号，从 `ffi.C` 调用并核对返回值；注册一个 Lua C 模块，记录 `nm` 与 `otool -L`。未完成须列 B1 前置风险；只有发现原理性障碍才据此判 no-go。
- [ ] 系统中文字体：从 App 沙盒访问 `/System/Library/Fonts` 下实际字体文件，调用 crengine 注册，核对返回值、字体名和可用性；记录准确路径及失败原因。
- [ ] 生命周期：分别观察 SDL 原始生命周期事件、Lua 收到的事件以及设备层是否触发保存。该版 SDL3 只在 watcher 同步发生命周期通知，不自动入队；须验证原生转投队列后的 Lua 交付，保持不从原生回调重入 Lua。
- [ ] 普通 PDF/扫描 PDF：打开和渲染样本，再实际调用 KOPT 前台重排；记录符号、错误或重排后的位图尺寸及图像证据。区分编译/链接问题与运行能力限制，不仅转述 hezi 文档。
- [ ] LuaSettings/DocSettings：验证现有 `backup()`、原地写入、同步及 `.old` 回退；覆盖文件修改时间不足/超过 60 秒。记录同步调用的真实返回值。
- [ ] 独立原语探针：临时文件写入 → flush/fsync → rename → 目录 fsync，保留旧版本；在关键阶段终止后检查完整版本与回退。必须注明这验证的是文件系统原语，**不是现有 App 已实现原子保存**。原子写入补全归 B5（#93）。

### 后续功能验收骨架

- [ ] 本地 EPUB/PDF：目录、字号/字体、三类笔记、恢复阅读、图片预览和横竖屏。
- [ ] 三条复制式导入：Files 暴露 Documents、系统文件选择器、“用 Just Reader 打开”；覆盖占位文件、重名、空间不足、失败清理和只读来源。
- [ ] 生命周期保存：失活即保存、续时不可用/过期、回前台补做、正常可调度时的秒级合并；已落盘版本在异常中断后可恢复。
- [ ] 书源：异步下载、进度、取消、超时、断网、慢网、多本并发、重试及跨域重定向敏感头策略。
- [ ] iPhone 窄屏、iPad 全屏、安全区、旋转、系统键盘与中文输入；覆盖候选词、粘贴和键盘收起，以后续 B4 规则为准。
- [ ] 模拟器升级安装：先保留已有进度与划线，用 `xcrun simctl install <UDID> <App.app>` 覆盖安装新版本，重新启动后核对数据。
- [ ] 能力关闭入口不显示；不开放后台重排/缩略图子进程、外部查询进程。
- [ ] KOPT 重排（C5，[#101](https://github.com/justinyanme/koreader/issues/101)）：文字 PDF（含双栏页）和无文本层的扫描 PDF 各一本，从版式书底栏的“Reflow”打开重排；输出可读，双栏合成一栏；调字号、滚动模式和翻页模式翻页、关闭重排都正常；记录单页 `reflowPage` 耗时和翻页耗时。翻页模式下一页由后台线程（pthread，不是子进程）预先重排。滚动模式翻页偏慢是因为 DocCache 在 iOS 上只有 16MB，归 [#150](https://github.com/justinyanme/koreader/issues/150)。
- [ ] 内存感知（C9，[#150](https://github.com/justinyanme/koreader/issues/150)）：DocCache 按设备给的可用内存定容量（可用内存 × 0.85 × 0.4，封顶 512MB；模拟器没有进程内存上限，按物理内存算，所以是 512MB）。打开扫描 PDF 开重排，滚动模式来回翻页，日志里不再出现 "Too much memory would be claimed by caching"，回到看过的页不再重新重排。
- [ ] 稳定版补验：进程内查询、Keychain、VoiceOver 五个流程、外接键盘；记录内存与性能变化。
- [ ] 仓库 spec 与全量回归由编排者在提交 TestFlight 前按 Q46 批量运行；本清单不授权逐票运行 spec 或做 Leaf5 实机验收。

### B3 存储与导入（#91）

依据 Q10、Q30、Q33、Q43。两台模拟器各执行一遍；`<data>` 为 `xcrun simctl get_app_container <UDID> me.justinyan.justreader data`。

- [ ] 布局：书在 `<data>/Documents`；设置、笔记、`docsettings/` 在 `<data>/Library/Application Support/koreader`；`<data>/Library/Application Support/koreader/cache` 是指向 `<data>/Library/Caches/koreader` 的软链。Files 的"我的 iPhone/Just Reader"里只有书，没有 `.sdr`、`Inbox` 或 KOReader 自己的文件夹。
- [ ] Files 放入：在 Files 里把 EPUB 放进"我的 iPhone/Just Reader"，回到 App 后书出现在书架（回前台由 B5 广播 `Resume`；B5 合入前以重启或关掉导入页代替，注明是哪种）。
- [ ] 缓存清理：删除 `<data>/Library/Caches` 下的全部内容后重启，书、进度、笔记都在，缓存目录自动重建。
- [ ] 文件选择器：导入页"从“文件”导入"→"选择文件"，系统选择器弹在 App 上（CLI 可验）。在选择器里选书要点按，归入真机复核。
- [ ] 用 Just Reader 打开（CLI：`xcrun simctl openurl <UDID> file:///<宿主机路径>/x.epub`，App 运行中和未运行时各一次）：书进入 Documents 并打开，`Documents/Inbox` 不残留。打开 App 自己 Documents 里的书时，系统直接给原路径，书原地打开、不能被移动或删除。PDF 默认由系统"预览"打开（我们注册为 Alternate），需要在分享菜单里选 Just Reader。
- [ ] 重名：再次导入同一本书，提示"已在这里"并保留原书；导入内容不同但同名的书，存为"X (2).epub"并明确提示，原书不变。
- [ ] "文件"页：根为 Documents，面包屑从主目录开始，在主目录按返回离开"文件"，没有"上一级"。导入页"从电脑传书"写 Files 路径和 Finder 文件共享，不出现 USB、Android 路径或沙盒绝对路径；iPad 上写"我的 iPad"。
- [ ] 容器路径变化：读过几本书后用 `xcrun simctl install` 覆盖安装（模拟器上数据容器的 UUID 每次都会变），启动后 `settings.reader.lua`、`history.lua`、`settings/*.lua`（文件头注释除外）里没有旧 UUID，sidecar 在 `docsettings/<新容器>/Documents/` 下，`cache` 软链指向新容器，书架、进度、划线都在（迁移见 `frontend/device/sdl/iosstorage.lua`）。
- [ ] 备份（Q33）：数据目录不做备份排除，没有设置 `isExcludedFromBackup`。凭据（书源密码、KOSync）首版以明文随 iCloud/Finder 备份；iCloud 备份由 Apple 加密，Finder 备份是否加密取决于用户在 Finder 里的设置，不能假定。

## 真机复核

由 owner 在需要体验时执行，建议 B1–B8 完成后首轮、C6 再做完整一轮。模拟器的速度、宿主进程 RSS 与供电状态不能替代真机结果。

### 安装与记录

- [ ] 使用最终 Just Reader 工程/发布流程，显示名 `Just Reader`、Bundle ID `me.justinyan.justreader`、开发 Team `V88UWDRASU`；不要把阶段 A 的 `rocks.koreader.ios` 实验包当作最终包。
- [ ] 按 D0/B1 实际交付的构建与签名说明安装：开发签名、OTA 或 TestFlight。确认 iOS 真机 arm64 构建，没有混入模拟器产物。发布任务及具体产物路径待相应票填写。
- [ ] 如采用 Xcode 开发安装，在工程选择 owner 的 Team 和已登记设备，安装后断开调试器、从桌面启动；如系统要求，按系统提示完成开发者模式/信任设置。
- [ ] 记录 App 版本/提交、安装渠道、设备型号、系统 build、可用存储、样书 SHA-256、屏幕方向与字号。升级安装前备份已有阅读数据。

### 两台设备分别复核

- [ ] iPhone 17 Pro Max 与 iPad Pro 11 英寸（M5）：重新执行上面的三项性能目标与至少 30 分钟连续阅读。记录温度、内存峰值、异常终止和具体操作。
- [ ] 后台、锁屏、来电打断、系统真实内存回收、升级安装后，进度与划线不丢；不要用手动强退等同于系统回收，记录实际终止方式。
- [ ] 真实屏幕亮度、中文输入、系统文件选择器、分享、Files/Finder 文件共享与 iCloud 未下载文件。
- [ ] 文件选择器（B3，模拟器只验到弹出）：在选择器里选 iCloud Drive 和"我的 iPhone"里的书各一本（多选）；书被复制进 Documents 并上架，`tmp/*-Inbox` 不留副本，源文件不变。取消不提示；未下载到本机的云盘文件（断网时选 iCloud 里只在云端的书）给出原因。
- [ ] Files 放入（B3）：在 Files App 里把书拖进"我的 iPhone/我的 iPad › Just Reader"，回到 App 后出现在书架（B5 接上回前台的 `Resume` 之前，以重启 App 代替）；Files 里看不到 `.sdr`、`Inbox`。Safari 下载、邮件附件的"用 Just Reader 打开"各做一次。
- [ ] Finder 文件共享（B3）：Mac 连接设备，在 Finder 的设备窗口"文件"标签里把书拖到 Just Reader 上，书出现在书架；反向从 Just Reader 拖出书也可。Files 的"我的 iPhone/我的 iPad › Just Reader"同样核对。
- [ ] TestFlight/开发包升级安装后，数据容器路径如有变化，进度、划线、历史、收藏都在（B3 的启动迁移）。
- [ ] 在可比较的亮度、网络和阅读时长下记录耗电；模拟器不提供电池门禁数值。
- [ ] VoiceOver 实际朗读与操作五个核心流程；外接键盘按最终支持范围验收。
- [ ] KOPT 重排：用真实的扫描书和文字 PDF 重做上面的 C5 项。确认真机上 `ffi.load("pthread")` 能解析（翻页模式后台预重排生效，日志无报错），记录长页重排位图的内存峰值；#150 合并前后各记一次滚动模式翻页耗时。
- [ ] 内存感知：连续阅读扫描 PDF（开重排，滚动模式，至少 30 分钟）时，记录 App 的峰值内存（Xcode 内存仪表或 Instruments），以及有没有被系统杀掉（jetsam）。被杀时记下设备、系统版本，以及日志里的 `memoryAvailable:` 一行（`os_proc_available_memory` 的值；真机上不应出现 `hw.memsize` 回退），评估是否要降低 DocCache 的上限。
- [ ] 真机任一目标不达标也停下评估；在报告追加真机记录，不能用模拟器通过覆盖失败。

### C4 外接键盘（#100，未验收）

本票已完成模拟器 Release 构建、472/472 符号门禁、`kodev run`、两台模拟器打开 EPUB，
并观察到 SDL 的 `native`、`hasKeys`、`hasKeyboard` 从 false 变为 true；记录和截图见
[external-keyboard.md](external-keyboard.md)。这不代表下面的按键行为已经验收。

本机 computer-use 接口无法取得 Simulator 窗口（持续报 `cgWindowNotFound`），因此
I/O → Keyboard → Connect Hardware Keyboard 的断开/重连、真实左右键及 Esc 收面板
**均未验收**。advisor 已裁定不继续阻塞 PR；由 owner 用 iPad 加外接键盘完成以下复核。

- [ ] 先不接键盘，打开 EPUB，确认触控翻页；保持工具栏和进度面板打开，再连接键盘。
  第一下 Esc 收起面板，第二下收起工具栏；在只有工具栏时接上键盘，第一下 Esc 也能收起它。
- [ ] EPUB 和 PDF 正文中，左右键分别翻到前后页；在已经接着键盘的状态下重新启动 App，
  左右键也直接可用。上下键保留原有语义。
- [ ] 工具栏保持打开时断开键盘，触控仍能关闭工具栏、呼出面板并翻页；重新连接后，
  第一下左右键可翻页，第一下 Esc 可关闭已打开的工具栏/面板。
- [ ] 按住 Shift 或 Ctrl 时断开键盘，再重新连接，普通左右键仍能翻页；没有滞留修饰键或持续翻页。
- [ ] 接着键盘打开搜索、笔记编辑等 InputDialog：默认不显示虚拟键盘时，硬件键盘文本能经
  SDL 正常输入、编辑和提交；断开后仍能使用虚拟键盘。这条文本输入路径在 iOS 上尚未验收。
- [ ] App 在后台时连接或断开键盘，回前台后首个按键/触控可用；记录设备、系统、App 提交、
  实际页码与面板变化及异常。若恢复模拟器窗口，再补做 Connect Hardware Keyboard 菜单切换。

### B6 书源异步下载（#94，部分未验收）

模拟器（两台 iOS 27.0，Release，474 符号门禁通过）已做：对本机两个源（`localhost:8080` 为书源、
`:8081` 为另一源）用启动补丁按时间线点封面、`simctl io screenshot` 截图。结果：
`canForkProcesses` 为 false，下载走 URLSession 桥；四本并发都完成，只打勾不打开；
下载期间打开长按面板，UI 循环最长间隔 0.13–0.27 s；500 失败有提示、可重试；
取消后临时文件立即删除；跨域 302 的第二跳不带 `Authorization` 和 CF 头，同源 302 带；
没有 HEAD 请求；切后台 60 s 后回前台，显示"后台时下载已停止"，不会假完成；
缓存目录和 `tmp/` 都没有残留。证据在本机 `/Volumes/T5/github/ios-evidence/94/`，
不公开；日志里有宿主机路径。以下只能在真机上确认，**未验收**：

- [ ] 手指点封面下载时，可以继续翻页、进分类、再点别的书；进度条持续前进，再点一次立即取消。
- [ ] 下载中关 Wi-Fi，或进入信号很差的地方：该书显示失败，再点封面重试能下完；主目录没有半截文件。
- [ ] 下载大书时锁屏或切到别的 App，等一分钟以上再回来：要么已完成（打勾），要么显示
  "后台时下载已停止"；不能停在"下载中"，也不能出现打了勾却打不开的书。
- [ ] 连 Cloudflare Tunnel 后的真实 NAS 书源：封面、下载都正常；若书源把下载 302 到别的域，
  仍能下完（第二跳不带 Service Token 是预期行为）。
- [ ] 离开书源页时正在下的书全部取消，并提示下载已取消。

iOS 的下载走 URLSession，会校验 TLS 证书；luasec 那条路径（墨水屏、iOS 上的目录请求）默认不校验。
所以用自签名证书的书源在 iOS 上能浏览，下载却显示通用的"无法连接"。owner 的 NAS 在 Cloudflare 后面，
证书有效，不受影响。

### B5 生命周期保存（#93）

2026-10-25 的 Release 构建与两台独立 iOS 27.0 模拟器记录见 [lifecycle-save.md](lifecycle-save.md)，base 补丁见 [fork PR #3](https://github.com/justinyanme/koreader-base/pull/3)。首次符号门禁 478/478；B3 合并后重建为 484/484，均无 loose dylib。原生 watcher 只申请续时、投递事件与记录状态，没有 Lua FFI callback。

- [x] 正常主循环下变更后约 3 秒合并保存；两台磁盘中 xpointer、划线内容和范围匹配。
- [x] 切到其他 App 再返回；真实 SDL 通知触发当前事件内同步保存并结束续时，Resume 可见。
- [x] 后台等待 5 秒后 terminate，重新打开恢复最后成功保存的进度和笔记。
- [x] 保存写入一半、替换前、备份 rename 后、替换后四处 terminate：只恢复完整旧版或新版，备份窗口通过 `.old` 恢复。
- [x] **B3（#91）合并后覆盖安装复验通过**：两台 93- 模拟器各读到第 86 页、添加 3 条笔记，正常落盘后 simctl install 覆盖；Data/Application UUID 均变化，重开后页码、EPUB xpointer、3 条笔记内容及范围与迁移后的 metadata 全部匹配。原阻塞已解除，详细 UUID/证据见 lifecycle-save.md。
- [ ] 锁屏/解锁、来电打断、系统真实内存回收：**未验收**，交 owner 真机复核。当前 simctl CLI 没有锁屏操作，screen power off 不能当锁屏；禁止为此操作 Simulator.app。
- [ ] 原生续时被拒绝/过期、写入失败后前台补做，以及内存警告释放缓存：假桥/持久化 spec 已编写，**按 Q46 未运行**；真实 UIKit 过期与内存警告另由 owner 复核。
- [ ] Docker 全量与 Leaf5 回归：按 Q46 留给 TestFlight 前批量运行，本票未运行。

失败边界：3 秒只是在主循环正常可调度、存储可写时的目标；崩溃、主循环阻塞、存储失败不保证只丢几秒，要求是已落盘数据不损坏，能恢复到最后一个完整版本（旧目标或 `.old`）。

### 每次复核记录模板

| 字段 | 填写 |
| --- | --- |
| 日期 / 执行者 | 待填 |
| App 版本 / 顶层与 base SHA / 渠道 | 待填 |
| 设备 / OS build / 样书 SHA | 待填 |
| 冷打开 / 第二次打开 | 待填 |
| 30 次翻页原始样本 / 中位数 / 最慢值 | 待填 |
| 30 分钟起止 / 内存 / 耗电 / 异常 | 待填 |
| 后台 / 锁屏 / 回收 / 升级后的数据核对 | 待填 |
| 失败项 / 日志或截图 / 复验条件 | 待填 |
| go/no-go 与后续处理 | 待填 |
