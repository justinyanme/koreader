# B4：dp、安全区和窄屏交付记录

对应 #92；依据 decisions Q5/Q6/Q7/Q25/Q39/Q46、ADR-0008、B0 的
[窄屏清单](narrow-screen-survey.md)，以及 T0 的 point/pixel 表。

## Lua 和文档已完成，原生集成等待 B1

- iOS 屏幕实例按完整 framebuffer / SDL window 的宽度取得 pixel/point，
  `scaleBySize`、`scaleByDPI` 均为 `ceil(dp × scale)`；`display_dpi = 160 × scale`
  是 dp 标尺，不是真实 PPI。T0：iPhone 3px/pt、iPad 2px/pt；44dp 分别为
  132px、88px，即 44pt。旧的 `screen_dpi` 设置不改变 iOS 控件大小。
- `iosnative/safearea.lua` 使用
  [SDL_GetWindowSafeArea](https://wiki.libsdl.org/SDL3/SDL_GetWindowSafeArea)，
  不增加 Swift 或 `ko_ios_*` 桥。桥返回 SDL window 坐标的四边 inset；设备层
  向内取整到像素 viewport。可用内容为安全区，完整 buffer 留作整屏底色。
- 只注册一次触摸平移，后续修改同一 offset 表；尺寸、像素尺寸、安全区事件
  复用 SetDimensions → ScreenResize → RedrawCurrentPage，再重建 FileManager
  的原有通知路径。正文位置沿用 ReaderRolling 的内部历史，不存第二份位置。
- R1：390dp 为两列 123dp 封面；书架 123×178、gap 22、gutter 61；
  书源 123×164、gap 20、gutter 62。低于 457dp 时关闭书源的缩小封面换行数逻辑。
- R2：按每条轨道实际档距判断，小于 33dp 时向点按方向走一档；绘制尺寸不变。
- iOS 的最小触控尺寸能力值为 44dp，扩展 PillButton、ShelfWidgets.Tappable
  的命中区域，搜索框、文字动作、chip 也受益；默认设备值为 0，保持墨水屏命中区域。
- PRODUCT 的 Users、Operating Context、Capabilities、Accessibility，以及
  DESIGN 的两档布局、内容彩色、LCD refresh 注记已更新。未修改 design/demo。

## iPad 观察项裁定

| B0 项 | 本票处理 | 理由 |
| --- | --- | --- |
| P1 封面放大 | 保留原有按英寸阈值算列数 | 单凭宽度大于 600dp 加上限会改变墨水屏横屏；advisor 要求零回归，本票不另加规则。iOS 的列数仍取决于点标尺及实际宽度。 |
| P2 字体网格变宽 | 保留 2–5 列 | 属于既有大屏比例布局，没有溢出，不引入第三套平板布局。 |
| P3 列表行变长 | 保留全宽行 | 沿用目录页和我页的比例布局；没有遮挡或放不下。 |
| P4 工具栏图标较散 | 保留均分 | 保留相同导航与可点击单元，不因 iPad 引入另一套工具栏。 |
| P5 居中卡片留白 | 保留 458dp / 416dp 上限 | 原有设计意图，避免卡片和笔记行长随屏幕无限增长。 |
| P6 默认边距未限 38 字 | 留给 owner 后续决定 | 墨水屏横屏也有相同行为；本票不改变默认书籍排版。已选边距的既有上限保持。 |

## 离屏渲染证据

基线为本分支起点 `4f3ff7d1d`。从 git archive 得到基线 Lua，当前分支为另一套
Lua 源；两者使用同一份现有 macOS Emulator 库、字体和已编译语言目录。运行目录、
设置、缓存、样书副本均在 `/tmp/jr-92-render`，owner 主检出只读。

运行 [render-b4.lua](../../tools/ios/render-b4.lua)，没有加载 commonrequire 或任何
spec。每个尺寸单独进程；每次重建相同绝对路径的 KO_HOME，固定显示时间，避免路径、
时钟或旧元数据造成无关差异。书源用确定性假 feed，使用真实入口和页面构建；阅读
使用随测试数据提供的 juliet.epub 副本。现有编译语言目录包含中英混合文案，图片只
证明这些输入的布局，不替代 B1 后真实 iOS 包、完整中文文案及最大界面字号的冒烟。

每组 11 页：书架、导入、阅读、工具栏、排版、进度、目录、笔记、书源、书源空状态、我。
原始截图和日志保留在 `/tmp/jr-92-render/captures/{before,after}/<尺寸>/`；
[comparison.json](b4-layout/comparison.json) 记录每张 PNG 前后 SHA-256。
PNG 文件字节一致比逐像素一致更严格；没有把截图比较称为已运行 spec。

| 尺寸 / 标尺 | PNG 完全一致 | 预期差异 |
| --- | --- | --- |
| 600×800，Emulator，142dpi，短边 600dp | 11 / 11 | 无 |
| 1264×1680，Emulator，300dpi，短边 600dp | 11 / 11 | 无 |
| 1680×1264，Emulator，300dpi，短边 600dp | 11 / 11 | 无，覆盖墨水屏横屏 |
| 390×844，B0 的 1dp=1px 标尺 | 9 / 11 | 书架、书源落实 R1；R2 不改变绘制 |
| 820×1180，B0 的 1dp=1px 标尺 | 11 / 11 | 无，P1–P6 均保持原有布局/行为 |

代表截图：

| Emulator 600dp | Emulator Leaf5 等效竖屏 | Emulator Leaf5 等效横屏 |
| --- | --- | --- |
| ![600](b4-layout/600x800-shelf.png) | ![1264 portrait](b4-layout/1264x1680-shelf.png) | ![1680 landscape](b4-layout/1680x1264-shelf.png) |

| 390 书架 | 390 书源 | 390 排版 | 820 书架 |
| --- | --- | --- | --- |
| ![390 shelf](b4-layout/390x844-shelf.png) | ![390 sources](b4-layout/390x844-sources.png) | ![390 typeset](b4-layout/390x844-typeset.png) | ![820 shelf](b4-layout/820x1180-shelf.png) |

## 验证与待完成项

测试已编写、按 Q46 未运行：`ioslayout_spec.lua`（接缝 C，真实设备初始化及
输入分发配假桥/假窗口，包括已保存的非零逻辑旋转，物理安全区重建后恢复逻辑轴）；
`narrowscreen_spec.lua`（接缝 B 书架及共享规则）；
`readertypesetpanel_spec.lua`（接缝 A，横竖屏及 inset 高度变化后同一正文位置）。
未做 Leaf5 实机验收。Lua 文件仅做 loadfile 语法解析，diff 做空白检查。

按 implement 技能做了两路只读 code-review（基线 `4f3ff7d1d`）：Standards
无硬性问题，1 项可选的触控矩形重复代码建议保留现状；Spec 找到 1 项软件旋转后把
逻辑宽高误作物理宽高的问题，已在 `5ae104e77` 修复并补 spec，原审查者复核通过。
该复核没有运行测试；B1 后的实际 iOS 验证仍须完成。

B1 合并并收到通知前，未改 base、platform/ios、Project.swift、kodev、make。
下列原生事项尚未完成，不能据此声称 #92 已满足全部验收：

1. Rebase 到 master；在 base fork 的独立小 PR 中转发 SAFE_AREA_CHANGED 和
   PIXEL_SIZE_CHANGED，并修复 resize 时旧 viewport / full_bb 的释放与重建。
   Lua 的 iOS resize 目前以该 framebuffer 契约为前提；不得单独把本票当作完整原生实现合入。
2. 按 B1 清单加入 SDL_GetWindowSafeArea 的导出/符号门禁，补隐藏状态栏的 plist 键。
3. `./kodev build ios`，创建 jr-92 前缀的 iPhone 17 Pro Max、iPad Pro 11 M5
   iOS 27.0 模拟器，CLI 安装/启动/截图冒烟；需要旋转 GUI 时先申请。
4. 核对真实包安全区、整屏背景与夜间反色、彩色内容、触控尺寸、旋转位置和两设备
   全部页面；补实际记录。fork PR 先合，再开/完成主仓库 PR，正文 Closes #92。
