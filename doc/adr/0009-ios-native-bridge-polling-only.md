# iOS 原生桥只用 C ABI 函数加 Lua 轮询，不用 FFI callback，不开第二个 Lua VM

iOS App 必须关闭 LuaJIT 的 JIT，`LJ_OS_NOJIT` 同时禁用 FFI callback；KOReader 现有的 `runInSubProcess`（书源下载、封面提取、后台重排）依赖 fork，iOS 没有。我们决定：所有原生能力（生命周期、安全区、亮度、文件选择器、分享、URLSession 下载）都以 `ko_ios_*` 风格的 C ABI 函数暴露给 `ffi.C`，状态由 Lua 在 UIManager 循环里轮询，原生侧不回调 Lua；不开第二个 Lua VM，也不让多个线程碰同一个 Lua VM 或同一个非线程安全的引擎实例。三处 fork 调用按任务各自替换，不做通用任务框架。代价是进度和事件有一个 tick 的延迟，长任务要自己拆成可轮询的状态机。

## Considered Options

- FFI callback 让原生线程直接回调 Lua：解释器模式下不可用，且有重入风险。
- 用线程跑第二个 Lua VM 做后台任务：要为每个任务复制状态和模块加载，收益配不上复杂度。
- 保留现成移植的"同步执行 + 临时文件"兼容层：下载期间界面冻结，取消按钮失效；后台重排的父子进程逻辑放进主进程会卡死或退出 App。
