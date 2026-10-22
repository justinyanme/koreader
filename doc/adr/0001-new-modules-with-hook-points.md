# 新界面写成新模块，原有模块只加挂钩点

这个 fork 要按微信读书墨水屏版重做书架、工具栏、排版面板等界面，同时还要持续拿到上游 KOReader 的修复。我们决定：新界面写成独立的新模块；原有模块（比如 `ReaderMenu`、`ConfigDialog`、文件浏览器）只改最少的代码，用来让它们可以被替换；每月把 `upstream/master` merge 进 fork 的 master，不用 rebase。

## Considered Options

- 硬分叉、随意改：几个月后就合不进上游的修复，而上游几乎每天都在提交。
- 纯插件加 userpatch、核心零改动：书架首页和底部配置条这种深层界面，靠插件很难替换干净。
