# iOS 原生层用 Swift + UIKit 写，Xcode 工程由 Tuist 生成

Just Reader 的界面全部由 Lua 画进 BlitBuffer，窗口和 scene 归 SDL3；原生层只负责启动 Lua VM 和 `ko_ios_*` 桥（[ADR-0009](0009-ios-native-bridge-polling-only.md)）。owner 决定：原生层用 Swift 写，只用 UIKit 和 Foundation，不用 SwiftUI，不新写 Objective-C；Xcode 工程由 `platform/ios/` 下的 Tuist 清单生成，Info.plist 的键写在清单里，生成的 `.xcodeproj`/`.xcworkspace` 不入库，Tuist 版本在仓库里固定。hezi 移植里的 Objective-C 只作参考：启动器约 4KB，目录选择器约 11KB，而且后者做的是授权目录加 bookmark，我们只做复制式导入，用不上。

## Considered Options

- 原样搬 hezi 的 Objective-C 和 xcodegen `project.yml`：能省掉重写，但量很小，owner 也已经选定 Swift 和 Tuist。
- SwiftUI：原生层没有自己的界面，只弹文件选择器、分享面板这类系统控制器，挂可访问性元素；SwiftUI 只会在 SDL 的窗口外面多包一层宿主。

## Consequences

- 桥函数用 Swift 的 `@c(ko_ios_…)` 导出 C ABI（Swift 6.4 已验证），仍由 Lua 轮询；这些符号进显式导出列表，并过 `nm` 门禁。
- Swift 不能导入函数式宏，调 Lua C API 时改用对应的函数，比如用 `lua_settop` 代替 `lua_pop`、用 `luaL_loadstring` 加 `lua_pcall` 代替 `luaL_dostring`。
- 系统控制器弹在 SDL 的视图控制器之上，不另建 UIKit 界面。
