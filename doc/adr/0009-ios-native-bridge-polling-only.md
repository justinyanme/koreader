# iOS 原生桥只用 C ABI 函数加 Lua 轮询，不用 FFI callback，不开第二个 Lua VM

iOS App 必须关闭 LuaJIT 的 JIT，`LJ_OS_NOJIT` 同时禁用 FFI callback；KOReader 现有的 `runInSubProcess`（书源下载、封面提取、后台重排）依赖 fork，iOS 没有。我们决定：所有原生能力（生命周期、安全区、亮度、文件选择器、分享、URLSession 下载）都以 `ko_ios_*` 风格的 C ABI 函数暴露给 `ffi.C`，状态由 Lua 在 UIManager 循环里轮询，原生侧不回调 Lua；不开第二个 Lua VM，也不让多个线程碰同一个 Lua VM 或同一个非线程安全的引擎实例。三处 fork 调用按任务各自替换，不做通用任务框架。代价是进度和事件有一个 tick 的延迟，长任务要自己拆成可轮询的状态机。

## Considered Options

- FFI callback 让原生线程直接回调 Lua：解释器模式下不可用，且有重入风险。
- 用线程跑第二个 Lua VM 做后台任务：要为每个任务复制状态和模块加载，收益配不上复杂度。
- 保留现成移植的"同步执行 + 临时文件"兼容层：下载期间界面冻结，取消按钮失效；后台重排的父子进程逻辑放进主进程会卡死或退出 App。

## Consequences

- 生命周期保存不靠从原生重入 Lua。原生侧的 SDL 事件 watcher 在失活、进后台时只申请后台续时（`beginBackgroundTask`）并让事件正常入队；Lua 主循环在 `SDL_PollEvent` 返回后优先处理该事件，在同一次处理里同步调用 `UIManager:flushSettings()` 和 `ReaderUI:saveSettings()`，保存完再调原生函数结束续时。
- 续时不是固定时长保证。保存从 `willResignActive` 就开始；续时标识无效时照常保存；过期回调在原生侧立即结束任务并置标志，Lua 在保存步骤之间查该标志，先写进度、笔记、设置，过期后跳过缓存、缩略图等非必要项；回前台时检查"保存未完成"标志补做一次。
- 写入原子性依赖 `LuaSettings` 现有的临时文件、fsync、改名并保留 `.old` 的写法（`.sdr` 用同一个类），被挂起时文件只会是旧版或新版。这条要在 iOS 文件系统上验证。
- 笔记和进度变更后几秒内合并落盘，是正常可调度时的目标，不保证崩溃、主循环阻塞或存储失败时只丢几秒；对这些情形的要求是已落盘的数据不损坏、能恢复到上一个完整版本。
- 下载桥不自动跟随重定向，3xx 和 Location 交回 Lua，由 `opdsclient` 已有的跳转循环统一判断次数上限、https 降级和敏感头同源（[ADR-0004](0004-opds-original-browser-as-fallback-only.md)）。桥不含任何策略。
