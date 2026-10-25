# C2 凭据迁移（#98）

依据 decisions.md Q22、Q33、Q46 和 ADR-0004、0009、0010。

`Device.bridge.keychainAvailable` 为 true 时使用三函数 Keychain 桥；unsupported 桩为 false。
不检查 `isIOS`。其他设备继续使用原有明文设置；日志加固对所有设备生效。
原版 `opdsbrowser.lua` 不改动，也不解析 Keychain 引用。

Swift 使用 Generic Password，service 为 `me.justinyan.justreader.credentials`，
`AfterFirstUnlockThisDeviceOnly`，不启用同步。Lua 的 get 区分 `not_found` 和其他错误；
set/delete 返回成功或错误，删除不存在的条目成功。FFI 使用长度和 malloc/free 传递字节串，
空串、Unicode、内嵌 NUL 都可往返。错误仅含数字 OSStatus，不含系统描述或凭据。

每个书源保存一个不透明 `credential_ref`，指向包含 Basic 密码、Cloudflare Client ID 和
Client Secret 的 JSON 包；用户名留在设置里。KOSync 原先保存的是可用于认证的 MD5
`userkey`，现在用 `userkey_ref` 引用。请求、编辑草稿和登录状态查询临时读取凭据，
不把解析结果放回设置记录。丢失条目时书源返回认证失败，显示“登录失败 → 编辑书源”；
KOSync 显示未登录，推送、拉取和重试队列都不会用空凭据发请求。

每次启动在旧版设置迁移之后处理 OPDS/KOSync 文件，包括尚未加载或已禁用的插件。
先写 Keychain，成功才清掉明文字段并保存引用；失败的记录保留原样，下次启动重试，
没有全局完成标记。新建/编辑/登录时 Keychain 写入失败只提示重试，不回退保存明文。
编辑采用新条目；引用和净化的备份保存成功后才删除旧条目，登出/删除也按此顺序。
如果进程恰在写 Keychain 后终止，可能留下未引用的 Keychain 条目，但不会丢掉原凭据。

持久化直接使用 `LuaSettings:flush`，依赖 B5（#93）的原子写入。
迁移和后续凭据保存用当前数据替换 `.old`，不生成 `.old.old`；每次启动仍检查并净化备份，
可补做中断的清理。B5 合入后、C2 合并前需要 rebase 并复核其 flush 接口。
不排除任何备份目录或文件；书、笔记、进度照常备份。Finder 备份是否加密取决于用户设置，
不能假定已加密。ThisDeviceOnly 条目不会迁移到新设备，需要重新登录。

日志不输出书源请求 URL、服务器状态文本、KOSync 整段响应/异常；失败只记静态说明或数字码。
KOSync 每个请求关闭 Spore 的线路调试，不影响其他 Spore 客户端。

## 2026-10-25 模拟器记录

- worktree `94`，分支 `feat/98-ios-keychain`；独立模拟器 `C2-Keychain-iPhone`，
  iPhone 17 Pro Max / iOS 27.0，UDID `9D6D4CCD-399A-4165-B3E0-4B4B84D72DA4`。
- 按规定设置 `CCACHE_BASEDIR`、获取 `/tmp/justreader-ios-build.lock` 后运行
  `./kodev build ios`：Release 构建成功，478 个导出符号门禁通过，无独立动态库。
- `simctl` 安装、启动，真实 Security 桥完成 Unicode/内嵌 NUL 的字节串往返和重复删除；
  缺失 get 返回 `not_found`。全程没有打开或关闭 Simulator.app。
- 在 App 数据容器种入合成 Basic/CF/KOSync 凭据和 `.old`。启动后主文件和备份均只留引用；
  本地 `localhost:18098` 认证服务收到书源和 KOSync 请求，分别返回 200。
  KOSync 真实登录流程成功，设置里没有 `userkey`。
- 保存数据快照，执行 `simctl uninstall`、`simctl keychain <UDID> reset`、重装并恢复快照。
  原引用仍在，书源显示 `Login failed` 和 `Edit source`；KOSync getter 返回未登录。
  合成 EPUB 和 `.sdr` 笔记文件恢复前后 SHA-256 一致。
- 迁移前后和恢复后的 debug 控制台、主设置和 `.old` 扫描合成密码、CF ID/Secret、
  KOSync 密码与摘要，匹配数为 0。日志只记录认证是否成功，不记录请求头。
- 证据在本机 worktree 的忽略目录 `koreader-ios-arm64-apple-ios27.0-simulator/c2-evidence/`，
  不提交含沙箱路径的原始日志。截图经 `simctl io screenshot` 获取。
- 已编写桥适配、迁移重试/幂等/备份清理、FileManager 书源编辑删除/恢复、KOSync 生命周期、
  “我”页面登录状态与日志 spec。**测试已编写、按 Q46 未运行**；未做 Docker 全量或 Leaf5。
  修改的 Lua 文件仅做语法编译检查，不执行 spec。GUI/真机项目见 acceptance.md。
