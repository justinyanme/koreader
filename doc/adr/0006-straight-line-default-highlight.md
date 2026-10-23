# 新划线默认直线，样式选择移到设置；旧的马克笔、波浪线照常显示

取代 [ADR-0003](0003-wavy-highlight-style.md) 的前提和样式行。

ADR-0003 的前提是微信读书的划线有马克笔、直线、波浪线三种样式，所以我们加了上游没有的波浪线，并在黑色划线气泡里放了一行样式选择。2026-10-23 在 BOOX Leaf5 上采集的微信读书墨水屏版 2.1.2 只观察到一种直线划线，选词浮层里也没有样式行（[13-highlight-added](../../design/references/weread-eink-leaf5-2026-10-23/07-selection-and-lookup/13-highlight-added.png)、[14-highlight-actions](../../design/references/weread-eink-leaf5-2026-10-23/07-selection-and-lookup/14-highlight-actions.png)）。我们决定（[DECISIONS.md](../../design/references/weread-eink-leaf5-2026-10-23/DECISIONS.md) K07）：

- 新划线默认是直线（`underscore`），和实机一致。
- 选词浮层里去掉样式行。
- 默认样式的选择移到 设置 → 阅读 → 划线样式。它读写上游已有的全局设置 `highlight_drawing_style`，不另起新的设置项。
- 只有从没显式保存过 `highlight_drawing_style` 时，新划线才用直线。已经保存过的值照用，不改写。这些值可能来自旧气泡的样式行、原版菜单里的长按，或新的设置入口。
- 已有划线按各自记录的样式显示，马克笔（`lighten`）和波浪线（`wave`）照常画。不做数据迁移，也不删任何样式。

## Considered Options

- 只留直线，删掉马克笔和波浪线：已有划线会丢样式，否则就要迁移数据。不能借“和微信一样”删用户的数据。
- 保留选词浮层里的样式行：和实机不一致。ADR-0003 的前提在这一版实机里已经不成立。
- 所有人一律改成直线默认，不管之前保存过什么：会悄悄改掉用户自己选的样式。

## Consequences

- 判断有没有“显式保存过”，只看全局的 `highlight_drawing_style`。在触屏设备上（新的划线界面只在触屏设备上启用），本 fork 一直让它优先于每本书的 `highlight_drawer`（`ReaderHighlightBubble:onReadSettings`）。上游每次关书都会把当前样式写进这本书的 `highlight_drawer`（`ReaderHighlight:onSaveSettings`），看不出是不是用户自己选的。所以全局值不存在时，新划线一律用直线，不退回到每本书自动存下的值；否则打开过的书都会继续用马克笔。这本书原来的 `highlight_drawer` 关书时原样写回，不被直线默认改掉（`ReaderHighlightBubble:onSaveSettings`），这样用上游 KOReader 或非触屏设备打开同一份笔记文件时，样式不变。没有触屏的设备仍走上游的划线界面和上游的样式规则。
- 新界面不再提供单条划线改样式。实现 K07 时试过把它放到“长按删除划线”这个次级入口，但那是隐藏手势，长按不够久会被当成点按，直接删掉划线，误删风险太大，所以去掉了（PR #76 review）。全局样式只在 设置 → 阅读 → 划线样式 选，它只管以后的新划线，不改已有划线。已有划线按各自记录的样式照常显示，马克笔和波浪线都不受影响。点按划线出的是新浮层，所以上游按条改样式的对话框在触屏设备上也不再出现；没有触屏的设备仍走上游界面，可以照旧改。
- 波浪线仍然是 fork 独有的样式，ADR-0003 记下的代价不变：用上游 KOReader 打开同一本书时，波浪线划线不会显示。`readerhighlight.lua` 和 `readerview.lua` 里把波浪线标成 fork 独有样式、指向 ADR-0003 的注释继续有效；`readerhighlightbubble.lua` 里给样式行写的那条注释，随样式行一起删掉。
- 想法不属于划线样式。只有想法、没有显式划线的条目，正文里只画想法标记，不画直线（DECISIONS J05）。
