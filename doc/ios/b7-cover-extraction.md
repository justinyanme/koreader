# B7：封面提取与无 fork 任务

依据：[#95](https://github.com/justinyanme/koreader/issues/95)、[Q12 / Q46](decisions.md)、[ADR-0009](../adr/0009-ios-native-bridge-polling-only.md)。

## 行为

- `Device:canForkProcesses() == true`：封面提取、后台重排、页面缩略图继续使用现有子进程。能力位默认值保持 `true`；iOS 变体由 B2 设置为 `false`。
- `false`：封面在主进程逐本提取。沿用书架每批最多 40 本的调度；每本之间经过 `nextTick` 和 100 ms 的延迟阶段，给输入和重绘留出机会。取消会移除待执行任务，任务 identity 阻止过期回调恢复旧批次。单本 Lua 异常记日志后继续；正在进行的单本同步提取不能中断。
- 每本完成后，书架重读不含封面 blob 的轻量元数据，更新进度；可见时刷新网格。原文件浏览器继续使用已有的缓存更新轮询。
- 无 fork 时不启用局部重排，不显示其设置，字体和行距变更走前台完整排版。已有的全局和单书局部重排偏好保留；不创建后台协调用的 mmap，不进入子进程等待或父进程退出路径。
- 页面缩略图选择**关闭**。页面浏览菜单和快捷动作选项隐藏，直接动作也不打开它；缩略图请求立即返回空结果且不排队。Book map 保留，点击或键盘选择直接跳页。
- `Trapper:dismissableRunInSubprocess` 复用现有阻塞回退，返回 `true, task()`；不提供单次执行内的取消。`dismissablePopen` 属于 C1，书源下载属于 B6。

## CRE 缓存核实

不能把“取封面不排版”等同于“不写 cr3cache”：

1. [CreDocument:loadDocument(false)](../../frontend/document/credocument.lua) 把 metadata-only 标志交给引擎；`getCoverPageImage` 使用已加载的文档，不主动排版。
2. 引擎的 EPUB metadata-only 分支提前返回，但非 EPUB 格式仍可能进入 `LVDocView::ParseDocument`。
3. DOM 存储超过内存预算时，`ldomDataStorageManager::compact` 会调用 `createCacheFile`，不需要先排版；文档关闭时 `LVDocView::close` 调用 `updateMap`，会把已有映射写回。

核对来源为本仓库 pin 的 koreader-base `33b43b5b21a2f2aa7a8b5ad53b6d83d3954f51c0` 的 `cre.cpp`，及其 crengine `f335f7a97e240f505bb8a0dfb721fcb7912a7824` 的 [`lvdocview.cpp`](https://github.com/koreader/crengine/blob/f335f7a97e240f505bb8a0dfb721fcb7912a7824/crengine/src/lvdocview.cpp)、[`epubfmt.cpp`](https://github.com/koreader/crengine/blob/f335f7a97e240f505bb8a0dfb721fcb7912a7824/crengine/src/epubfmt.cpp)、[`lvtinydom.cpp`](https://github.com/koreader/crengine/blob/f335f7a97e240f505bb8a0dfb721fcb7912a7824/crengine/src/lvtinydom.cpp)。

因此每本提取仍用原来的临时目录 `cache/tmpcr3cache`。无 fork 路径用 `pcall` 包住提取，异常时关闭已打开的文档；成功或异常后均立即调用 `CreDocument.cacheInit()` 恢复正常缓存配置、清除覆盖标志，再返回 UI 循环。下一本重新设置临时目录。正常阅读缓存不会被整书架的提取填满。可重建的临时目录仍由原有 `cleanUp` 生命周期清理。

## 单本耗时与后续模拟器验收

**当前没有模拟器实测数字。** 按 owner 协调，本票只保留测量点，模拟器实测等 B1 合并后进行。不能据此宣称 100 本书架响应性或复杂单本停顿已经达标。

每次无 fork 提取输出 info 日志：

```text
BookInfoManager: in-process extraction <filepath> took <elapsed_ms> ms success: <boolean>
```

测量范围从单本提取前到文档清理、缓存恢复完成，包含加载、封面解码缩放压缩及数据库写入；不包含两本之间的 100 ms 调度间隔、引擎首次初始化和书架重建。Lua 异常的提取也记录耗时，并另写警告。计时 spec 中的固定数值只验证记录接口，不是性能测量。

B1 可用后，在 iPhone 17 Pro Max 和 iPad Pro 11 英寸（M5）模拟器分别：

1. 准备至少 105 本书，包括大图片封面和较大的非 EPUB 格式；清理可重建封面缓存，记录设备、构建提交、书目规模和样本尺寸。
2. 首次打开书架，持续翻页、点书、关闭再打开；检查封面逐本出现、换页取消后旧回调不再改动已退出的书架。
3. 收集以上日志，补记首次提取和复杂单本的耗时、最大值及可感知停顿。复杂单本超过可感知停顿时，记录具体书目和时长，作为后续线程化评估依据；本票不加工作线程或第二个 Lua VM。
4. 改字体、字号和行距，检查前台完整排版和位置保持；确认没有后台等待、父进程检查或退出 App。

| 环境 | 105+ 本逐本出现与交互 | 单本耗时及复杂单本停顿 | 字体 / 行距前台排版 |
| --- | --- | --- | --- |
| iPhone 17 Pro Max 模拟器 | 待 B1 | 待 B1 | 待 B1 |
| iPad Pro 11 英寸（M5）模拟器 | 待 B1 | 待 B1 | 待 B1 |
| owner 真机复核 | 后续补充 | 后续补充 | 后续补充 |

## Spec 与执行状态

`bookinfomanager_spec.lua` 覆盖 105 本逐本调度、取消和过期回调、异常继续、完成回调取消、子进程路径、真实元数据提取、计时日志及成功/异常后的缓存恢复。`shelf_spec.lua` 补充单本完成刷新、隐藏书架和取消通知。`reader_nofork_spec.lua` 覆盖前台字号/行距重排、偏好保留、后台入口能力门、缩略图关闭和保留子进程路径、Book map 跳页。`trapper_spec.lua` 覆盖 wrapped/unwrapped 回退、多返回值（含 nil）和原子进程路由。

测试已编写、按 Q46 未运行；Docker 单 spec、全量和 Leaf5 实机验收均留给编排者在 TestFlight 前批量执行。
