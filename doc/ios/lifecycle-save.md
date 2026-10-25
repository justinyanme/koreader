# B5 生命周期保存实现与待集成项

对应 [#93](https://github.com/justinyanme/koreader/issues/93)、decisions.md Q14/Q26/Q36/Q46/Q47/Q48，以及 ADR-0009 Consequences。测试已编写、按 Q46 未运行；没有做 Leaf5 实机验收。

## 保存顺序与恢复边界

- `LuaSettings:flush()` 与 `DocSettings:flush()` 的主 metadata 文件共用 `settingswriter`：同目录 `.tmp` → 检查 write、flush、fsync、close → 满足原有 60 秒规则时将目标 rename 为 `.old` → rename 临时文件为目标 → fsync 目录。
- 临时写入失败时目标不变；备份 rename 失败则不替换目标；替换失败会把 `.old` 改回目标。如果回滚也失败，保留完整 `.old`，加载器仍能恢复。两个 rename 之间中断，加载器会回退 `.old`；残留 `.tmp` 不参与加载，由下一次写入覆盖/清理。目录同步失败会向上传递失败，但不会破坏已经替换的完整文件。
- `ioslifecycle` 只由 iOS 设备安装。will-resign-active 对应的 SDL WILL_ENTER_BACKGROUND 立即同步保存；同一次失活的后续通知不重复保存成功的数据，但仍释放 watcher 可能取得的续时。
- 必要项顺序为：ReaderUI 的 SaveSettings（收集进度与笔记）→ `.sdr` → 全局设置 → UIManager 的 FlushSettings 广播。可选上下文防止广播再次保存同一个 ReaderUI。自动笔记导出、metadata 归档、DocCache 序列化和 KOSync 的 Suspend 上传延后到必要项之后，每项开始前检查过期；必要项失败时也跳过可选项。
- 续时未获准仍保存；过期仍尝试必要项。原生过期回调立即结束任务并置 sticky 标志，不回调 Lua。Lua 无论保存成功或抛错均结束续时；失败或跳过工作保留未完成标志，回前台补做。
- watcher 已申请但 Lua 尚未领取的句柄单独保留；即使先过期，Lua 领取的仍是原句柄，不能被一次新申请掩盖过期。同一次失活期间的过期状态一直保留到回前台，已排队的 WILL/DID 重复通知不能重新开启可选工作。FlushSettings 的插件处理器向 LuaSettings 传递可选上下文；写入失败会标记未完成，并保留插件 dirty 标志供前台补做。未传上下文时沿用各处理器原行为。
- PageUpdate、PosUpdate、AnnotationsModified 在 ReaderUI 的分发完成后调用设备可选钩子。从首次变更起 3 秒到期，后续连续变更不推迟截止时间；关书/失活时取消定时器。普通设备没有该钩子。
- 内存警告仅清 DocCache 的 RAM/已登记磁盘缓存、GlyphCache、ImageCache 并 GC；不递归删除数据根目录，不释放仍被控件引用的图像。

3 秒是主循环正常可调度、存储可写时的目标。崩溃、主循环阻塞、存储失败时，不保证只丢几秒；验收要求是已落盘的数据不损坏，能恢复到最后一个完整版本（目标旧版或 `.old`）。没有终止回调也不能破坏已保存版本。

## Suspend / Resume 审计

审计范围为 `frontend/`、`plugins/` 中的定义、别名和动态安装，包括 `_onSuspend` / `_onResume`；不是只搜函数声明。下表为 B1 合并前的 Lua 审计，PR 正文应链接此表并注明新增门控。

不广播 `RequestSuspend`：DeviceListener 会调用 `UIManager:suspend()`，下一 tick 进入 SDLPowerD 的 `beforeSuspend()`，再走设备 `_beforeSuspend()` 的 flush、Suspend、输入抑制、关闭按键重复。iOS 需要在当前事件中同步保存，并由 UIKit 管理系统休眠，因此只在必要项之后广播一次 Suspend；回前台广播 Resume。重复 UIKit/scene 恢复通知不重复广播；首个恢复通知仍可触发 B3 sweep。

| 文件 / 处理器 | 动作与 iOS 判断 |
| --- | --- |
| `device/devicelistener.lua` Resume | 恢复手势输入；保留，不走设备电源动作。 |
| `readerdevicestatus.lua` Suspend / Resume | 停止/恢复电量和内存检查定时器；自动重启另由 `canRestart` 保护，iOS 为 false。`/proc` 不存在时内存检查直接跳过。 |
| `readercoptlistener.lua` Suspend 别名 / Resume | 停止/恢复页眉刷新；没有屏保创建或硬件操作。 |
| `readerfooter.lua` Suspend 别名 / Resume | 停止/恢复页脚刷新、重置初始进度；仅绘制。 |
| `readerrolling.lua` Resume | 更新页眉电量状态；保留。 |
| `readerview.lua` Resume | 重置自动保存计时；保留。 |
| `ui/network/networklistener.lua` Suspend / 条件 Resume | 断 Wi-Fi 受 `hasWifiManager`、恢复受 `hasWifiRestore` 保护；iOS 均 false。仅停止活动检查与清理网络标志。 |
| `screensaverwidget.lua` Suspend / Resume | 改屏保锁标志；iOS 不走 Screensaver 创建路径，`supportsScreensaver=false`、`canSuspend=false`，本票不调用屏保。 |
| `screensaverlockwidget.lua` Suspend / Resume | 更新屏保锁及等待手势提示；同上，无实例就没有处理器被调用。 |
| `toast.lua`、`notification.lua` Resume 别名 | 消费输入相关事件以免传给 InputContainer；不做设备动作，顶层广播仍会传给其他窗口。 |
| `autosuspend.koplugin` Suspend / Resume | 会安排 suspend/shutdown/standby；模块加载已有 `canSuspend` 门控，iOS 禁用；内部 shutdown/standby 另有能力门。 |
| `autodim.koplugin` 动态 Suspend / Resume | 停止亮度渐变、恢复用户主动启用的自动调暗计时；需要 `hasFrontlight`。只恢复自己之前改变的亮度，不进入休眠/关闭系统屏幕。 |
| `autowarmth.koplugin` 动态 Suspend / Resume | 温度由 `hasNaturalLight` 控制；夜间反色可保留。**新增 `hasEinkScreen` 门控**：白天关前光的菜单、定时安排和执行只对墨水屏启用，LCD Resume 不修改 `fl_was_on`。 |
| `autoturn.koplugin` Suspend / Resume | 暂停/恢复当前自动翻页，保存自身偏好；无设备休眠动作。 |
| `statistics.koplugin` Suspend / Resume | 保存统计数据库、暂停/恢复阅读计时；保留。 |
| `systemstat.koplugin` 与其 Widget Suspend / Resume | 记录时间与次数；无电源动作。 |
| `batterystat.koplugin` 与其 Widget Suspend / Resume | 累计电量使用并标记失活；无关前光/关 Wi-Fi。 |
| `calibre.koplugin` Suspend | 断开 Calibre 应用连接，不关闭系统网络；保留。 |
| `httpinspector.koplugin` Suspend / Resume | 停止/按用户设置重启 HTTP 服务；iptables 仅 Kindle 分支，iOS 不进入。 |
| `readtimer.koplugin` Resume | 根据真实时间重排闹钟或立即提醒；保留。 |
| `profiles.koplugin` Resume | 执行用户设置的恢复配置；Dispatcher 执行前检查能力，不可用的 suspend/reboot/Wi-Fi 等动作会被过滤。 |
| `kosync.koplugin` 动态 Suspend / Resume | Resume 安排拉取；Suspend 上传为可选工作。本票传入保存上下文时将上传延后并允许过期跳过；关 Wi-Fi 已由 `hasWifiManager` 保护。未传上下文时沿用原行为。 |

## B1 合并后集成

当前 `platform/ios/Background.swift` 独立于 D0 源码目录，未改 Project.swift、base、kodev 或 make；不能据此声明模拟器验证通过。

1. 收到 B1 完成通知后 rebase master，按 B1 的桥头文件导入 SDL，编译 Background.swift。在 SDL 初始化后、运行 Lua 前调用 `ko_ios_background_install()`，失败须记录并作为冒烟失败处理。
2. 将以下六个符号加入 B1 的保留/导出清单并通过 Release `nm` 门禁：`ko_ios_background_install`、`ko_ios_background_begin`、`ko_ios_background_end`、`ko_ios_background_expired`、`ko_ios_background_save_incomplete`、`ko_ios_background_set_save_incomplete`。Lua 适配器在 `iosnative/background.lua`；已有 iosbridge 契约和 features 包含本票五函数，无需修改其他功能的实现。
3. 在 base fork 单独开只增改动的小 PR：把标记信封和直接排队的生命周期通知转为 `EV_SDL`。信封为 `SDL_EVENT_USER`，`user.windowID=0x4B4F4935`，`user.code` 为原始 SDL app event，范围 TERMINATING 到 DID_ENTER_FOREGROUND；检查标记和范围，不把普通用户事件误转为生命周期事件。app 事件在 Lua 主循环取出时立即交设备层处理，不再另排 nextTick 保存。
4. `./kodev build ios`，创建 `93-` 前缀的 iPhone 17 Pro Max 与 iPad Pro 11 英寸 M5 / iOS 27.0，CLI 安装、启动、截图。不得复用其他 builder 的模拟器；需要 Simulator GUI 时先向 advisor 申请。
5. 将下面场景合入 `acceptance.md` 并记录实际结果；代码和文档审查完成后再 push 并对 master 开 PR，正文写 `Closes #93` 与“测试已编写、按 Q46 未运行”。不合并 PR。

## 待执行的模拟器冒烟与真机复核

两台模拟器均记录版本、UDID、运行时、书籍路径、进度（PDF 页码 / EPUB xpointer）、笔记数量与可辨识内容，并在重新打开后核对 `.sdr` 可读及数据。

| 场景 | 操作与判定 | 当前状态 |
| --- | --- | --- |
| 切其他 App | 修改进度与笔记，立刻切后台，再返回；检查 watcher 入队、同步保存、结束续时及 Resume。 | WAITING_B1 |
| 锁屏 | 同样修改后用 CLI 锁屏/解锁；恢复到最后成功保存的版本。若系统 CLI 不支持，申请 GUI 后执行，不伪造为已通过。 | WAITING_B1 |
| 后台终止 | 修改后后台等待约 5 秒，`simctl terminate` 后重开；恢复进度/笔记。 | WAITING_B1 |
| 覆盖安装 | 保存后保留沙盒，用 `simctl install` 安装新包再重开；数据不损坏。 | WAITING_B1 |
| 保存中断 | 在临时写入、备份 rename 后、替换后分别终止；重开只能读到完整旧版或新版，必要时通过 `.old` 恢复。不可把未执行的时序当结果。 | WAITING_B1 |
| 无续时 / 过期 / 写入失败 | 假桥 spec 覆盖同步保存、必要项先写、可选项跳过、结束续时与前台补做；不按成功运行报告。 | 已编写，Q46 未运行 |
| 秒级合并与缓存清理 | spec 覆盖持续变更不推迟 3 秒截止、关书取消、内存警告清缓存后书与笔记仍可读。 | 已编写，Q46 未运行 |

真机复核由 owner 执行：来电打断与系统真实内存回收，以及上述五种场景；模拟器 terminate 不能代替真实系统回收。按 Q46，Docker 全量与 Leaf5 验收留给 TestFlight 前批量回归。
