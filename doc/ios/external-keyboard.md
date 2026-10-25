# C4：外接键盘翻页（#100）

依据：[issue #100](https://github.com/justinyanme/koreader/issues/100)、[Q20 / Q46](decisions.md)。

## 实现

只在 SDL 的 iOS 设备变体上，`hasKeys` 和 `hasKeyboard` 随硬件键盘连接状态切换。
`hasDPad` 保持关闭，触控一直可用。左右键沿用阅读模块的翻页绑定，Esc 沿用 SDL 的
`Back` 映射，依次退出嵌套面板、面板、工具栏；上下键保留原有导航语义。

不需要 Swift。锁定版本 SDL 3.4.16 的
[UIKit 后端](https://github.com/libsdl-org/SDL/blob/release-3.4.16/src/video/uikit/SDL_uikitevents.m)
已经订阅 GCKeyboard 连接与断开通知，并通过 `SDL_AddKeyboard` / `SDL_RemoveKeyboard`
维护设备列表。[SDL_HasKeyboard](https://wiki.libsdl.org/SDL3/SDL_HasKeyboard)
返回这个列表是否非空，不以屏幕键盘的显示与否判断。接缝 C 的 `keyboardConnected()`
由 `iosnative/keyboard.lua` 查询 SDL；未实现时返回 `nil, "unsupported"`，维持触控能力。

现有 `ffi/SDL3.lua` 没有把 `SDL_EVENT_KEYBOARD_ADDED/REMOVED` 或窗口焦点事件传给前端。
因此只在 iOS 输入实例上扩展 backend 表：原样调用阻塞的 `waitForEvent`，返回后查询
状态，再原样返回全部结果，包括 `EINTR` 和超时。SDL 已处理通知，Lua 即使丢弃该
通知也能观察到状态。初始化时另查一次；没有定时器、额外唤醒或回调进入 Lua。

能力位变化后复用 `PhysicalKeyboardConnected/Disconnected`，刷新静态输入绑定和已显示
控件；已打开的工具栏也能补上 Esc。断开时清空未释放的修饰键和重复状态。
Desktop / Emulator 继续使用原来的输入 backend，墨水屏的输入实现没有改动。

## 验证记录与待办

- 已编写 `iosdevice_spec.lua`（接缝 C）及 `ioskeyboard_spec.lua`（接缝 A+C）：初始连接、
  断开、重连、unsupported、设备状态隔离、等待参数与全部返回值保留、共享 backend
  不变、EPUB/PDF 首个左右键翻页、热插拔后的 Esc 和触控翻页。
- 按 Q46，所有测试均未运行；不做逐票 Leaf5 验收。
- B1 合并前不改 base、Tuist 工程或构建脚本，不构建 iOS，不声明模拟器验收通过。
- B1 合并后需 rebase，在其 SDL FFI 导出清单确认保留 `SDL_HasKeyboard`，然后用
  `./kodev build ios` 构建并完成下面的模拟器冒烟。

## 模拟器冒烟（B1 合并后）

自建名称以 `100-` 开头的 iOS 27.0 iPhone 17 Pro Max 和 iPad Pro 11 英寸 M5
模拟器。安装、启动和截图用 `simctl` CLI。需要 Simulator GUI 时先按 builder consultation
协议发 `question` 申请独占，获准后才能操作，结束后归还。

1. 启动时关闭 I/O → Keyboard → Connect Hardware Keyboard，打开 EPUB；触控翻页，
   打开进度面板，保持工具栏与面板显示。
2. 启用 Connect Hardware Keyboard，第一下 Esc 关闭面板，第二下关闭工具栏。
   左右键各翻一页；上下键保留原有行为。
3. 保持工具栏打开，关闭 Connect Hardware Keyboard，再通过触控关闭工具栏并翻页。
   重新连接后，第一下左右键仍翻页，第一下 Esc 仍能关闭已打开的工具栏。
4. 换 PDF 重复左右键和触控翻页；在已连接键盘的状态下重新启动 App，左右键直接可用。
5. App 进入后台期间连接或断开键盘，回前台后验证能力位和首次输入；重复连接与断开，
   确认没有卡住的 Shift/Ctrl 修饰状态、持续翻页或新增的定时轮询。
6. 两类模拟器记录实际结果、构建版本及截图；完成后归还 GUI。

真实硬件连接通知仍需 owner 在 iPad 外接键盘上复核；模拟器菜单行为以实际记录为准。
