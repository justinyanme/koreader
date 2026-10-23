# iOS 移植用 fork 的 koreader-base 子模块，不整体换成现成移植仓库

iPhone/iPad 移植需要改 `koreader-base` 的交叉编译、LuaJIT 配置、SDL3 适配和符号导出，现成移植 hezi/koreader-ios 也是靠一个独立的 base 分支做到的。我们决定：fork 为 `justinyanme/koreader-base`，`.gitmodules` 的 `base` 改指 fork；iOS 补丁合入 fork 的 master，尽量只增文件、不改上游文件；每月和 l10n（[ADR-0002](0002-forked-l10n-submodule.md)）一起把上游 base merge 进 fork。代价是所有平台的构建都从 fork 取 base，多一个要同步的子模块。

## Considered Options

- base 继续指上游，iOS 构建时临时打补丁：不可复现，每个人、每台机器结果不同。
- 整体改用 hezi 的两个仓库：会丢掉我们更新的上游代码、改版界面和 l10n fork。
