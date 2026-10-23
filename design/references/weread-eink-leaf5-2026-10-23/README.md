# 微信读书墨水屏版 · Leaf5 阅读界面实机参考

2026-10-23 在 USB 连接的 BOOX Leaf5 上逐项操作采集。微信读书墨水屏版 2.1.2（10245900），包名 com.tencent.weread.eink，Android 13，竖屏 1264 × 1680。

共 **185 张 PNG，16 个目录（首轮143张，补拍42张）**。图片是 ADB 原始截图，未裁切、加标注或调色。ADB 画面保留应用的彩色内容，不能代表墨水屏面板的实际灰阶、残影和刷新效果。编号按功能组织，允许跳号，并非逐秒录像或连续书页。

双击打开 [index.html](index.html) 可离线浏览缩略图、操作路径和原图；[screenshots.json](screenshots.json) 提供每张截图的路径、说明、尺寸与 SHA-256。下表可直接打开各功能目录。

主样本是书架上带私密标记的《蘋果之道：重新定義世界的50年》。社区与书末功能使用已经读完的《正念的奇迹》补录。补拍另用未读完的《审判（果麦经典）》验证书末行为。这些书呈现的顶部入口不同，不能把全部按钮当成任何书籍都同时具有的固定工具栏。

## 功能目录

| 目录 | 内容 | 张数 |
| --- | --- | ---: |
| [00-entry](00-entry/) | 书架、打开与最终位置 | 3 |
| [01-reader-navigation](01-reader-navigation/) | 阅读导航与工具栏 | 5 |
| [02-typography](02-typography/) | 字体、版式与段落 | 15 |
| [03-progress](03-progress/) | 进度、章节跳转与自动翻页 | 11 |
| [04-contents-and-search](04-contents-and-search/) | 目录与全文搜索 | 9 |
| [05-bookmarks](05-bookmarks/) | 书签及混合筛选 | 7 |
| [06-notes](06-notes/) | 笔记列表与空状态 | 7 |
| [07-selection-and-lookup](07-selection-and-lookup/) | 选词、查询、划线与想法 | 25 |
| [08-listening](08-listening/) | 听书与后台播放器 | 24 |
| [09-images](09-images/) | 书内图片 | 3 |
| [10-conversion-and-book-actions](10-conversion-and-book-actions/) | 繁简转换、书架与下载 | 4 |
| [11-handwriting](11-handwriting/) | 手写模式与手写笔记管理 | 8 |
| [12-book-ending](12-book-ending/) | 书末与读完状态 | 4 |
| [13-reading-preferences](13-reading-preferences/) | 全局阅读偏好 | 4 |
| [14-community](14-community/) | 书评、热门划线与书友想法 | 14 |
| [15-supplement](15-supplement/) | 补拍：入口、手势、进度与书末 | 42 |

## 对 KOReader 设计的直接证据

以下“实机观察”来自这批截图；“待评审问题”是后续设计建议，尚未修改 KOReader 代码或现有规范。

| 实机观察 | 截图证据 | 待评审问题 |
| --- | --- | --- |
| 目录与笔记都是全屏页；列表右下有上一页/下一页按钮，目录支持层级折叠。 | [目录](04-contents-and-search/01-contents.png)、[笔记](06-notes/01-notes-list.png) | 现有 DESIGN.md 的“目录/书签/笔记左侧抽屉”需要重新对照实机确认。 |
| 底部工具栏从左到右是返回、目录、笔记、进度、字体、听。类似太阳的图标打开进度面板。 | [工具栏](01-reader-navigation/01-toolbars.png)、[进度](03-progress/01-progress-panel.png) | 现有规范把亮度放在阅读工具栏，不能作为本版微信读书的复刻依据。 |
| 文字选中菜单是白底黑色描边，带三角指向；选词下划线、黑色水滴形手柄。 | [英文选词](07-selection-and-lookup/01-english-word-selected.png)、[页底选词](07-selection-and-lookup/21-bottom-of-page-selection.png) | 现有规范中的黑底菜单、反白选区及第二行划线样式，与本次采集不一致；这版未发现多样式选择。 |
| 中英文动作有差异：英文是翻译，中文是查询；图片长按仅划线和写想法。 | [中文](07-selection-and-lookup/17-chinese-text-selected.png)、[图片](09-images/01-image-long-press.png) | 选中对象类型应决定可用动作，菜单定位还应考虑页底空间。 |
| 字体面板在正文上方保留预览，以四行加减/滑块控制数值，字体名称自身展示字形。 | [字体面板](02-typography/01-font-panel.png)、[展开分类](02-typography/09-more-fonts.png) | 评审即时预览、数值反馈和更多字体的展开方式；字号重排期间需注意状态一致。 |
| 搜索、热门片段跳转在正文底部显示黑色导航条，含退出与回列表入口。 | [搜索条](04-contents-and-search/07-search-return-bar.png)、[热门片段](14-community/13-popular-highlight-jump.png) | 跳转后的阅读模式需要清晰退出路径；搜索条与普通工具栏的状态可分别建模。 |
| 书签和划线归入笔记列表；有书签时出现仅书签/全部的筛选，长按卡片打开底部删除确认。 | [混排](05-bookmarks/05-bookmarks-and-highlights-filter.png)、[确认层](05-bookmarks/06-bookmark-delete-confirmation.png) | 是否统一条目模型与类型图标，应结合 KOReader 现有能力评审。 |
| 自动翻页是独立状态，左下有设置胶囊，设置中可选速度、划线导读和关闭。 | [入口状态](03-progress/02-auto-page-turn.png)、[设置](03-progress/03-auto-page-turn-settings.png) | 需要明确开启状态、设置入口与停止路径。 |
| 听书有完整页和书架迷你条，返回原文仍可能继续播放。15秒跳转、切集和拖动松手在本次测试中会开始或恢复播放。 | [完整页](08-listening/16-listen-from-selection-playing.png)、[迷你条](08-listening/14-background-mini-player.png)、[拖动后](08-listening/23-seek-result.png) | 音频状态不能只跟随阅读面板生命周期；跳转是否恢复播放需作为明确产品决策。 |
| 擦掉笔迹后仍有手写页面卡片；必须在笔记列表删除该条目，数量才回落。 | [残留卡片](11-handwriting/09-erased-stroke-note-remains.png)、[最终42条](06-notes/07-final-note-count-restored.png) | 笔迹与手写笔记条目的生命周期需要区分；空笔记的保留或清理策略应明确。 |

## 已恢复与操作影响

- 主样本恢复到第7章“選單”原正文段落。字号22、字重2、寒蝉活宋体、原行距边距、首行顶格、段间距关闭，繁体正文均已核对。分页曾多次重算，首轮163/1272→87/648，补拍87/648→77/581；这不表示恢复到了另一段文本。
- 本次创建的私密测试想法、单词划线、多行划线、书签和手写笔记均已删除。主样本笔记数从初始42条恢复为42条，未删除原有笔记。
- 自动翻页和划线导读关闭；听书语速恢复1.0x、仅当前专辑开关关闭、定时关闭；音色未更改。最终已关闭书架迷你播放器。
- 《正念的奇迹》仍为原有读完状态，恢复到版权页；书友想法恢复隐藏。未点赞、评论或发表公开想法，也未移除书籍、退出账号或清理缓存。
- 阅读时长、最近打开排序、阅读/听书历史位置会随 walkthrough 更新。已触发整书可读内容下载；剪贴板最后一次测试复制内容为 PARC。这些历史和缓存未回滚。


## 补拍结论与恢复记录

2026-10-23 16:48–17:14补拍42张，集中在[15-supplement](15-supplement/)，原143张保持不变。需求标签与全部截图映射见[REQUIREMENTS.md](REQUIREMENTS.md)。

| 条目 | 实机结论 | 标签变化 |
| --- | --- | --- |
| A06 | 导入打开手机微信读书、电脑r.qq.com传书的说明页，没有本机文件选择器；只看说明并关闭。 | 待定→微信读书独有；本地导入入口A05仍可做 |
| A08 | 空选择、选2本、整架全选385本；粗黑边框/圆形勾，底部下载、移出书架、私密动作，取消退出。长按封面直接进入单选，没有独立菜单。 | 待定→可做（本地多选；账号动作另计） |
| A09 | 独立搜索输入页；“审判”结果先“在书架中搜索”，再“在书城中搜索”。 | 待定→可做（本地搜索页；书城L06仍独有） |
| A11 | 面具角标同帧XML的content-desc明确为“私密阅读”，底栏动作是“关闭私密阅读”；未切换隐私。 | 待定→微信读书独有 |
| B05 | 从书架/本地搜索结果重新进入阅读会出现“↑ 上滑显示工具栏”；静置65秒后消失，随后翻页不重现。精确超时未计时。 | 待定→可做 |
| E05 | 拖动跳转后浮出“返回原进度”，点击返回跳转前正文并收起工具栏。未确认灰点本身可点返回。 | 待定→可做（明确返回按钮路径） |
| R02 | 开启后左点87→88、右点88→89，左右均下一页；关闭后左点89→88→87。 | 待定→可做 |
| K08 | 连续长按拖动，以及先松手再拖手柄，扩选松手都会自动划线并使笔记42→43；单词长按松手本身只出现“划线”菜单。 | 待定→可做 |
| Q02 | 未读完书拖到100%到最后正文页；再向后翻显示“全书完”和“标记读完”，未自动标记；返回后书架仍无读完角标。 | 待定→可做 |
| N04 | 查《蘋果之道》目录与“注释”正文、选词测试所在章及《审判》26–29页，未找到可点击脚注；注释章不是脚注弹层。 | 仍待定，未穷举385本 |

角标证据：[长按封面原图](15-supplement/06-book-cover-long-press.png)及[同帧UI XML](15-supplement/06-book-cover-long-press.xml)。XML含原始无障碍标签，未修改应用私密状态；不能据此推断私密模式的全部云端规则。

补拍的两条自动划线都已单独删除，[笔记数恢复42](15-supplement/38-notes-restored-42.png)；《审判》恢复[26/296原正文](15-supplement/42-trial-final-position-restored.png)，《蘋果之道》恢复[“選單”原正文](15-supplement/44-final-reading-restored.png)（分页重算为77/581，按文字与插图对照）。[左侧下一页开关已恢复关闭](15-supplement/28-left-side-next-restored-off.png)，输入法恢复EN；没有实际导入、移除/删除书籍、切换私密或点击标记读完，也未改字体、段落、听书设置。

**未能完全回滚的测试痕迹**：首页搜索新增“审判”历史。[搜索页](15-supplement/43-search-history-cleanup-limit.png)只找到“清空”，长按、横滑未找到单条删除，为保留原有历史未清空。阅读时长、最近打开排序、服务端阅读记录会随操作更新；未尝试改应用数据库或回滚云端记录。因此只确认阅读位置、开关和测试笔记已恢复，不宣称所有历史已清除。

## 覆盖边界

覆盖本机本版本、这三本书中可见的主要阅读入口、面板、列表、确认层、加载与空状态。未穷举每个字号/字体/速度值或所有书籍条件。首轮书末样本原已读完；补拍《审判》未读完，最后正文页再翻一次出现“全书完”和手动“标记读完”入口，未点击。

未覆盖 PDF、横屏、脚注弹层（样本中未定位到可点击脚注）、实体翻页键、真实手写笔、听书音质、离线断网错误、登录/付费/分享和公开发布。静态 PNG 不能验证触摸延迟、翻页动画或墨水屏刷新效果。书评与词典的联网内容及计数仅为采集时快照。

## 每张截图与操作路径

下列路径从各组说明的入口开始；相邻编号可能来自不同轮次补录，不应按页码拼接为一次连续阅读。测试中的未修改动作（例如点赞、移除书架）只记录可见入口或确认层，不表示已经执行。

### 00-entry · 书架、打开与最终位置

微信读书启动后进入书架。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-bookshelf.png · 书架](00-entry/01-bookshelf.png) | 启动应用 → 书架 | 采集开始时的书架。 |
| [02-book-open.png · 打开书籍](00-entry/02-book-open.png) | 书架 →《蘋果之道》 | 无工具栏的原始阅读位置，第7章“選單”。 |
| [03-final-reading-position.png · 最终阅读位置](00-entry/03-final-reading-position.png) | 清理测试数据 → 重新打开《蘋果之道》 | 恢复到与02相同的正文段落；重排后页码发生变化。 |

### 01-reader-navigation · 阅读导航与工具栏

《蘋果之道》正文。不同动作截图取自采集期间不同的阅读位置。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-toolbars.png · 上下工具栏](01-reader-navigation/01-toolbars.png) | 正文 → 上滑显示工具栏 | 上方为书籍动作，下方为返回、目录、笔记、进度、字体、听书。 |
| [02-tap-next-page.png · 点击翻到下一页](01-reader-navigation/02-tap-next-page.png) | 正文 → 点击右侧翻页区域 | 翻页后的插图页。 |
| [03-tap-previous-page.png · 点击翻到上一页](01-reader-navigation/03-tap-previous-page.png) | 正文 → 点击左侧翻页区域 | 翻页后的文字页；全局“点击左侧翻到下一页”关闭。 |
| [04-swipe-next-page.png · 滑动翻页](01-reader-navigation/04-swipe-next-page.png) | 正文 → 横向滑动翻页 | 翻页后的插图页。 |
| [05-swipe-up-toolbars.png · 上滑唤出工具栏](01-reader-navigation/05-swipe-up-toolbars.png) | 正文 → 向上滑动 | 正文下方保留操作栏。 |

### 02-typography · 字体、版式与段落

正文 → 上滑显示工具栏 → 底部 A。调整会重新分页，截图中的其他参数可能处于中间测试值。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-font-panel.png · 字体面板](02-typography/01-font-panel.png) | 底部 A | 字号、字重、行距、边距四行控制，以及字体卡片。 |
| [02-font-size-increased.png · 增大字号](02-typography/02-font-size-increased.png) | 字体面板 → 字号加号 | 滑块显示24，正文实时重排。 |
| [03-font-weight-increased.png · 增大字重](02-typography/03-font-weight-increased.png) | 字体面板 → 字重加号 | 滑块显示3。 |
| [04-line-spacing-increased.png · 增大行距](02-typography/04-line-spacing-increased.png) | 字体面板 → 行距加号 | 行距滑块位置及正文排版反馈。 |
| [05-margins-increased.png · 增大边距](02-typography/05-margins-increased.png) | 字体面板 → 边距加号 | 正文宽度发生变化。 |
| [06-paragraph-indent.png · 段落设置入口](02-typography/06-paragraph-indent.png) | 字体面板 → 右上“首行顶格” | 首行顶格与首行缩进两个大卡片。 |
| [07-paragraph-indent-selected.png · 选择首行缩进](02-typography/07-paragraph-indent-selected.png) | 段落设置 → 首行缩进 | 选中卡片以黑底白字表示。 |
| [08-paragraph-spacing-enabled.png · 开启段间距](02-typography/08-paragraph-spacing-enabled.png) | 段落设置 → 首行缩进 → 段间距开关 | 开关开启状态。 |
| [09-more-fonts.png · 全部字体](02-typography/09-more-fonts.png) | 字体面板 → 查看更多 | 全部29、仓耳12、方正7、其他9的分类标签。 |
| [10-fonts-canger.png · 仓耳字体](02-typography/10-fonts-canger.png) | 查看更多 → 仓耳 | 分类筛选及字体名称的字形预览。 |
| [11-fonts-founder.png · 方正字体](02-typography/11-fonts-founder.png) | 查看更多 → 方正 | 分类筛选。 |
| [12-fonts-other.png · 其他字体](02-typography/12-fonts-other.png) | 查看更多 → 其他 | 分类筛选，当前字体为黑底卡片。 |
| [13-system-font-selected.png · 选择系统字体](02-typography/13-system-font-selected.png) | 查看更多 → 全部 → 系统字体 | 字体选中状态及正文变化。 |
| [14-original-settings-restored.png · 字体设置恢复](02-typography/14-original-settings-restored.png) | 恢复寒蝉活宋体、字号22、字重2及原行距边距 → 重新打开字体面板 | 最终核对：行距与边距滑块均回到初始靠左位置。 |
| [15-paragraph-settings-restored.png · 段落设置恢复](02-typography/15-paragraph-settings-restored.png) | 字体面板 → 段落设置 | 最终核对：首行顶格，段间距关闭。 |

### 03-progress · 进度、章节跳转与自动翻页

正文 → 上滑显示工具栏 → 底部进度图标（外观类似太阳）。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-progress-panel.png · 进度面板](03-progress/01-progress-panel.png) | 底部进度图标 | 百分比、剩余阅读时长、已读时长、笔记数、滑块及自动翻页入口。 |
| [02-auto-page-turn.png · 开启自动翻页](03-progress/02-auto-page-turn.png) | 进度面板 → 开启自动翻页 | 正文左下出现自动翻页设置胶囊。 |
| [03-auto-page-turn-settings.png · 自动翻页设置](03-progress/03-auto-page-turn-settings.png) | 自动翻页 → 左下设置胶囊 | 速度刻度、划线导读开关、关闭自动翻页按钮。 |
| [04-auto-reading-guide-enabled.png · 开启划线导读](03-progress/04-auto-reading-guide-enabled.png) | 自动翻页设置 → 划线导读 | 正文出现导读线；采集后恢复关闭。 |
| [05-progress-panel-after-navigation.png · 重新打开进度面板](03-progress/05-progress-panel-after-navigation.png) | 关闭自动翻页 → 导航到其他位置 → 进度图标 | 按钮恢复为“开启自动翻页”。 |
| [07-progress-drag-preview.png · 拖动进度预览](03-progress/07-progress-drag-preview.png) | 按住进度滑块 → 向右拖动，尚未松手 | 显示目标百分比，正文暂时保留原位置；另有旧位置灰色标记。 |
| [08-progress-jump-loading.png · 跳转加载](03-progress/08-progress-jump-loading.png) | 拖动进度 → 松手 | 中部出现“加载中…”的过渡状态。 |
| [09-progress-jump-result.png · 跳转完成](03-progress/09-progress-jump-result.png) | 松手后等待加载 | 目标正文与进度滑块。 |
| [10-tap-progress-track.png · 点击进度轨道](03-progress/10-tap-progress-track.png) | 进度面板 → 点击轨道靠左位置 | 跳到另一正文位置；未据此认定灰色点具有“返回”功能。 |
| [11-next-chapter.png · 下一章](03-progress/11-next-chapter.png) | 进度面板 → 滑块右侧箭头 | 正文跳到“麥金塔辦公室系統”。 |
| [12-previous-chapter.png · 上一章](03-progress/12-previous-chapter.png) | 进度面板 → 滑块左侧箭头 | 正文跳到“瘋狂般偉大”。 |

### 04-contents-and-search · 目录与全文搜索

正文 → 上滑显示工具栏 → 底部目录。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-contents.png · 目录首页](04-contents-and-search/01-contents.png) | 底部目录 | 全屏目录，含搜索框、层级、页码和右下分页按钮。 |
| [02-contents-section-collapsed.png · 折叠目录分组](04-contents-and-search/02-contents-section-collapsed.png) | 目录 → 点 PART 1 分组箭头 | 折叠后可看到后续分组。 |
| [03-contents-bottom.png · 目录底部](04-contents-and-search/03-contents-bottom.png) | 目录 → 右上“去底部” | 尾部章节、致谢、资料来源、注释、附录等条目。 |
| [04-search-input.png · 搜索输入](04-contents-and-search/04-search-input.png) | 目录 → 搜索框 | 键盘展开，全书搜索输入状态。 |
| [05-search-results.png · 搜索结果](04-contents-and-search/05-search-results.png) | 输入 PARC → 提交 | 按章节列出命中内容，关键词黑底反白。 |
| [06-search-hit-in-book.png · 跳转到命中正文](04-contents-and-search/06-search-hit-in-book.png) | 搜索结果 → 点击一条结果 | 命中正文及阅读工具栏。 |
| [07-search-return-bar.png · 搜索导航条](04-contents-and-search/07-search-return-bar.png) | 命中正文 → 收起工具栏 | 底部黑色搜索条包含关键词、返回结果列表及关闭入口。 |
| [08-search-no-results.png · 搜索无结果](04-contents-and-search/08-search-no-results.png) | 返回搜索 → 输入 qzxw987654321 → 提交 | 空结果提示“没有找到相关内容”。 |
| [09-search-exited.png · 退出搜索](04-contents-and-search/09-search-exited.png) | 返回命中正文 → 关闭底部搜索条 | 恢复普通正文。 |

### 05-bookmarks · 书签及混合筛选

正文工具栏右上书签入口；笔记列表也可从目录底部“书签”按钮进入。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-bookmarks-before.png · 添加前的笔记列表](05-bookmarks/01-bookmarks-before.png) | 底部笔记 | 初始共42条，未见仅书签筛选入口。 |
| [02-bookmark-added.png · 添加书签](05-bookmarks/02-bookmark-added.png) | 返回正文 → 顶部书签 | 右上黑色折角及“书签已添加”提示。 |
| [03-remove-bookmark-toolbar.png · 已加书签的工具栏](05-bookmarks/03-remove-bookmark-toolbar.png) | 有书签的正文 → 上滑工具栏 | 顶部图标下有“删除书签”动作状态。 |
| [04-bookmark-in-notes.png · 仅显示书签](05-bookmarks/04-bookmark-in-notes.png) | 打开笔记 → 仅显示书签 | 只有新加书签卡片，总数43。 |
| [05-bookmarks-and-highlights-filter.png · 显示全部笔记](05-bookmarks/05-bookmarks-and-highlights-filter.png) | 右上筛选 → 显示全部 | 书签与原划线混排，并使用不同类型图标。 |
| [06-bookmark-delete-confirmation.png · 删除书签确认](05-bookmarks/06-bookmark-delete-confirmation.png) | 仅书签列表 → 长按测试书签 | 底部“确认删除该笔记吗？”确认层。 |
| [07-temporary-bookmark-removed.png · 测试书签已删除](05-bookmarks/07-temporary-bookmark-removed.png) | 确认删除 → 笔记列表 | 恢复42条；该测试书签已清除。 |

### 06-notes · 笔记列表与空状态

正文 → 上滑显示工具栏 → 底部笔记。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-notes-list.png · 笔记首页](06-notes/01-notes-list.png) | 底部笔记 | 书籍概况卡、章节标题、圆角笔记卡片与分页按钮。 |
| [02-notes-next-page.png · 笔记下一页](06-notes/02-notes-next-page.png) | 笔记 → 右下下一页 | 使用分页按钮浏览列表。 |
| [03-existing-note-long-press.png · 笔记长按确认层](06-notes/03-existing-note-long-press.png) | 笔记 → 长按一条原有笔记 | 只查看删除确认，随后取消，未删除原有笔记。 |
| [04-note-jump-to-text.png · 笔记跳回正文](06-notes/04-note-jump-to-text.png) | 笔记列表 → 点击笔记卡片 | 跳到正文，并短暂以灰色标示对应内容。 |
| [05-notes-last-page.png · 笔记最后一页](06-notes/05-notes-last-page.png) | 连续点下一页至底部 | 下一页按钮禁用；末页可能与上一页重叠。 |
| [06-empty-notes-completed-book.png · 没有笔记](06-notes/06-empty-notes-completed-book.png) | 《正念的奇迹》正文 → 底部笔记 | 0条，提示可记录想法、划线与书签。 |
| [07-final-note-count-restored.png · 最终笔记数量核对](06-notes/07-final-note-count-restored.png) | 删除本次测试手写笔记 → 回笔记首页 | 最终恢复42条，与采集前一致。 |

### 07-selection-and-lookup · 选词、查询、划线与想法

《蘋果之道》正文 → 长按文字。测试想法使用英文标记“UI walkthrough temporary note”，仅自己可见，已删除。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-english-word-selected.png · 英文选词菜单](07-selection-and-lookup/01-english-word-selected.png) | 长按英文 PARC | 白底描边浮层，动作是划线、翻译、写想法、复制、听当前；黑色拖动手柄。 |
| [02-translation-result.png · 没有词条的翻译结果](07-selection-and-lookup/02-translation-result.png) | PARC 选词 → 翻译 | 只显示词语、全书繁转简、去书城搜索入口，未返回词义。 |
| [03-selected-text-bookstore-search.png · 按选词搜书城](07-selection-and-lookup/03-selected-text-bookstore-search.png) | 翻译结果 → 去书城搜索 | 以 PARC 为关键词的书城结果页。 |
| [04-write-thought-editor.png · 写想法编辑器](07-selection-and-lookup/04-write-thought-editor.png) | 返回正文 → 长按 PARC → 写想法 | 下方编辑区、引用、键盘和发表按钮。 |
| [05-private-visibility-indicator.png · 私密状态指示](07-selection-and-lookup/05-private-visibility-indicator.png) | 想法编辑器 → 查看“私密”标记 | 本次该标记不可点击，未打开可见范围菜单。 |
| [06-private-thought-draft.png · 私密想法草稿](07-selection-and-lookup/06-private-thought-draft.png) | 想法编辑器 → 输入测试标记 | 草稿输入状态。 |
| [07-private-test-thought-saved.png · 测试想法保存](07-selection-and-lookup/07-private-test-thought-saved.png) | 点击发表 | 页面提示保存成功；这是私密测试想法。 |
| [08-private-thought-detail.png · 正文上的想法卡片](07-selection-and-lookup/08-private-thought-detail.png) | 点击已保存想法所在词语 | 引用和作者内容卡，带赞与评论图标。 |
| [09-private-thought-full-detail.png · 自己的想法详情](07-selection-and-lookup/09-private-thought-full-detail.png) | 想法卡片 → 点击内容 | 全屏详情，明确显示“仅自己可见”，有删除入口。 |
| [10-thought-likes-tab.png · 想法的赞标签](07-selection-and-lookup/10-thought-likes-tab.png) | 想法详情 → 赞 | 查看空列表，未点赞。 |
| [11-test-thought-delete-confirmation.png · 删除测试想法确认](07-selection-and-lookup/11-test-thought-delete-confirmation.png) | 自己的想法详情 → 删除 | 删除确认层。 |
| [12-test-thought-deleted.png · 测试想法已删除](07-selection-and-lookup/12-test-thought-deleted.png) | 确认删除 → 回到正文 | 测试词语不再带该想法卡片。 |
| [13-highlight-added.png · 添加划线](07-selection-and-lookup/13-highlight-added.png) | 长按 PARC → 划线 | 选中菜单的第一项切换为“删除划线”。 |
| [14-highlight-actions.png · 已有划线菜单](07-selection-and-lookup/14-highlight-actions.png) | 再次长按测试划线 | 已有划线上的操作菜单。 |
| [15-test-highlight-removed.png · 测试划线已移除](07-selection-and-lookup/15-test-highlight-removed.png) | 点击删除划线 → 关闭菜单 | 测试单词划线已清除，原有其他划线保留。 |
| [16-copy-confirmation.png · 复制确认](07-selection-and-lookup/16-copy-confirmation.png) | 长按 PARC → 复制 | 黑底提示“已复制到剪贴板”。 |
| [17-chinese-text-selected.png · 中文选词菜单](07-selection-and-lookup/17-chinese-text-selected.png) | 长按“史丹佛”附近文字 | 识别出的选词为“丹佛”；中文菜单使用“查询”。 |
| [18-chinese-lookup-result.png · 查询加载](07-selection-and-lookup/18-chinese-lookup-result.png) | 中文选词 → 查询 | “查询中…”状态。 |
| [19-chinese-lookup-settled.png · 百科摘要](07-selection-and-lookup/19-chinese-lookup-settled.png) | 等待查询完成 | 丹佛百科释义与外部详情箭头。 |
| [20-encyclopedia-webview.png · 百科详情网页](07-selection-and-lookup/20-encyclopedia-webview.png) | 点击百科释义卡片 | 内嵌搜狗百科网页。 |
| [21-bottom-of-page-selection.png · 页底选词](07-selection-and-lookup/21-bottom-of-page-selection.png) | 在正文页底长按 Copy | 浮层放在选词上方，手柄位于页底。 |
| [22-english-translation-result.png · 英文翻译有词义](07-selection-and-lookup/22-english-translation-result.png) | Copy 选词 → 翻译 | 显示“复制”及百科释义摘要。 |
| [23-drag-to-highlight.png · 拖动扩大选区](07-selection-and-lookup/23-drag-to-highlight.png) | 返回正文 → 拖动选词手柄 | 多行文本下方出现持久划线；本次操作产生了一条测试划线。 |
| [24-expanded-test-highlight-removed.png · 扩大选区的测试划线已删除](07-selection-and-lookup/24-expanded-test-highlight-removed.png) | 长按新划线 → 删除划线 | 测试“用 X 代表剪下…”段落划线已清除。 |
| [25-listen-from-selection.png · 从选词开始听](07-selection-and-lookup/25-listen-from-selection.png) | 选词菜单 → 听当前 | 打开听书播放器，截图为三点加载状态。 |

### 08-listening · 听书与后台播放器

正文 → 底部“听”，或长按文字 →“听当前”。播放器中的三点表示加载，三角表示可播放，两竖线表示正在播放。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-listening-player-paused.png · 听书暂停状态](08-listening/01-listening-player-paused.png) | 底部听 → 暂停 | 封面、章节、定时、音色、语速、进度、原文、切集与集列表。 |
| [02-sleep-timer.png · 定时关闭面板](08-listening/02-sleep-timer.png) | 播放器 → 定时关闭 | 关闭、30、60、90分钟和本集结束后关闭入口。 |
| [03-sleep-timer-30-minutes.png · 设置30分钟](08-listening/03-sleep-timer-30-minutes.png) | 定时关闭 → 30 | 面板出现剩余倒计时；随后恢复关闭。 |
| [04-voice-selection.png · 音色选择](08-listening/04-voice-selection.png) | 播放器 → 当前音色 | 初始 AI男声2025A，包含更多音色入口。 |
| [05-more-voices.png · 更多音色](08-listening/05-more-voices.png) | 音色选择 → 更多音色 | 扩展后的分页音色列表。 |
| [06-more-voices-next-page.png · 音色列表下一页](08-listening/06-more-voices-next-page.png) | 更多音色 → 下一页 | 更多音色；未切换当前音色。 |
| [07-playback-speed.png · 语速设置](08-listening/07-playback-speed.png) | 播放器 → 语速 | 初始1.0x，以及“仅应用到当前专辑”开关。 |
| [08-speed-and-album-scope.png · 1.5倍与专辑范围](08-listening/08-speed-and-album-scope.png) | 语速 → 1.5x → 开启仅应用到当前专辑 | 测试后恢复1.0x和范围开关关闭。 |
| [09-episode-list.png · 集列表](08-listening/09-episode-list.png) | 播放器 → 66集 | 章节可拆分为多个音频分集，并显示各集时长。 |
| [10-episode-list-bottom.png · 集列表底部](08-listening/10-episode-list-bottom.png) | 集列表 → 去底部 | 尾部各集及页码按钮。 |
| [11-playback-loading.png · 播放请求加载](08-listening/11-playback-loading.png) | 播放器 → 播放/暂停测试 | 中心为三点加载态，不能据此判断已播放或已暂停。 |
| [13-return-to-original-text.png · 返回原文](08-listening/13-return-to-original-text.png) | 播放器 → 原文 | 回到文字阅读；保留采集时的搜索导航条，返回原文本身不负责关闭后台播放。 |
| [14-background-mini-player.png · 后台迷你播放器](08-listening/14-background-mini-player.png) | 播放器收起 → 返回书架 | 底部迷你条含播放状态、时间与关闭按钮。 |
| [15-mini-player-paused.png · 迷你播放器暂停](08-listening/15-mini-player-paused.png) | 迷你条 → 暂停 | 按钮显示播放三角。 |
| [16-listen-from-selection-playing.png · 从选词位置播放](08-listening/16-listen-from-selection-playing.png) | 选词 → 听当前 → 等待加载 | 中心暂停图标，显示当前朗读文字。 |
| [17-selection-playback-paused.png · 暂停朗读](08-listening/17-selection-playback-paused.png) | 正在播放 → 中心暂停 | 中心播放三角。 |
| [18-rewind-15-seconds.png · 后退15秒](08-listening/18-rewind-15-seconds.png) | 暂停后 → 左侧15秒按钮 | 位置改变，并恢复播放。 |
| [19-forward-15-seconds.png · 前进15秒](08-listening/19-forward-15-seconds.png) | 播放器 → 右侧15秒按钮 | 位置前进，处于播放状态。 |
| [20-next-episode.png · 下一集](08-listening/20-next-episode.png) | 播放器 → 下一集 | 标题从“第7章 麗莎”变成“第7章 麗莎_1”，开始播放。 |
| [21-previous-episode.png · 上一集](08-listening/21-previous-episode.png) | 播放器 → 上一集 | 返回“第7章 麗莎”，开始播放。 |
| [22-seek-drag-preview.png · 拖动听书进度](08-listening/22-seek-drag-preview.png) | 暂停 → 按住进度条 → 拖到中部但不松手 | 白底时间气泡，上方另显示目标时间，仍为暂停图标。 |
| [23-seek-result.png · 听书进度跳转](08-listening/23-seek-result.png) | 进度拖动 → 松手 | 跳转到55分钟附近，并恢复播放。 |
| [24-expand-mini-player.png · 展开迷你播放器](08-listening/24-expand-mini-player.png) | 暂停 → 收起 → 返回书架 → 点击迷你条正文 | 展开为完整播放器，保留暂停状态。 |
| [25-mini-player-closed.png · 关闭后台播放器](08-listening/25-mini-player-closed.png) | 收起至书架 → 点击迷你条 X | 迷你条消失；最终没有后台播放。 |

### 09-images · 书内图片

正文内的插图。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-image-long-press.png · 长按图片菜单](09-images/01-image-long-press.png) | 长按书内电脑插图 | 仅显示划线与写想法，动作少于文字选词。 |
| [02-image-preview.png · 全屏图片预览](09-images/02-image-preview.png) | 点击正文中的 Widths 插图 | 黑色背景，图片居中显示。 |
| [03-image-preview-zoom.png · 图片放大](09-images/03-image-preview-zoom.png) | 预览中双击图片 | 局部放大并超出屏幕边缘。 |

### 10-conversion-and-book-actions · 繁简转换、书架与下载

《蘋果之道》正文顶部工具栏。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-convert-to-simplified.png · 转为简体](10-conversion-and-book-actions/01-convert-to-simplified.png) | 顶部“简” | 正文变为简体，字体选择保持不变。 |
| [02-traditional-restored.png · 恢复繁体](10-conversion-and-book-actions/02-traditional-restored.png) | 顶部“繁” | 正文恢复原繁体；已核对文本。 |
| [03-bookshelf-action.png · 书架动作确认](10-conversion-and-book-actions/03-bookshelf-action.png) | 顶部已加入书架图标 | 出现“将…移出书架吗？”确认层，随后取消，未移除书籍。 |
| [04-offline-download-action.png · 离线下载](10-conversion-and-book-actions/04-offline-download-action.png) | 顶部云下载图标 | 提示已开始下载所有可阅读内容，右上显示下载状态。 |

### 11-handwriting · 手写模式与手写笔记管理

正文 → 上滑显示工具栏 → 顶部手写图标。使用 ADB 触摸输入模拟单条笔迹，未使用实体手写笔。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-handwriting-mode.png · 手写模式](11-handwriting/01-handwriting-mode.png) | 顶部手写图标 | 右上退出，底部独立上一页、画笔/橡皮擦、下一页。 |
| [02-test-stroke-and-eraser-selected.png · 笔迹与橡皮擦](11-handwriting/02-test-stroke-and-eraser-selected.png) | 画笔模式画一条水平线 → 点击橡皮擦 | 顶部正文留有测试线条，底部橡皮擦选中。 |
| [05-test-stroke-erased.png · 测试笔迹已擦除](11-handwriting/05-test-stroke-erased.png) | 橡皮擦选中 → 点击测试线条 | 测试线条消失；本次连续擦动未生效，点在线条上成功。 |
| [06-page-turn-in-handwriting-mode.png · 手写模式翻页](11-handwriting/06-page-turn-in-handwriting-mode.png) | 手写模式 → 下一页 | 底部专用翻页控件保留。 |
| [07-clean-reading-after-test-removal.png · 清理后的普通正文](11-handwriting/07-clean-reading-after-test-removal.png) | 退出手写 → 删除测试手写笔记 → 回原阅读段落 | 正文无测试笔迹，与00-entry最终位置相同。 |
| [09-erased-stroke-note-remains.png · 擦掉线条仍保留笔记](11-handwriting/09-erased-stroke-note-remains.png) | 擦除笔迹并退出 → 打开笔记列表 | 仍有带页面缩略图的手写笔记卡；擦除笔迹不等于删除笔记。 |
| [10-test-handwriting-delete-confirmation.png · 删除测试手写笔记确认](11-handwriting/10-test-handwriting-delete-confirmation.png) | 长按本次创建的手写缩略图卡片 | 底部删除确认层。 |
| [11-test-handwriting-removed.png · 手写笔记已删除](11-handwriting/11-test-handwriting-removed.png) | 确认删除 | 缩略图卡片消失；总数恢复见06-notes/07。 |

### 12-book-ending · 书末与读完状态

补充样本《正念的奇迹》，在采集前已经标记“读完”。未将主样本标记读完。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-completed-book-open.png · 已读完书籍再次打开](12-book-ending/01-completed-book-open.png) | 书架 →《正念的奇迹》 | 打开版权页，仍可正常阅读。 |
| [02-completed-book-contents-bottom.png · 目录尾部](12-book-ending/02-completed-book-contents-bottom.png) | 工具栏 → 目录 → 去底部 | 最后章节与作者简介入口。 |
| [04-book-end.png · 读完页面](12-book-ending/04-book-end.png) | 从尾部章节继续向后翻页至书末 | “已读完”、第47本、推荐值和评价分布。 |
| [05-book-end-toolbars.png · 书末工具栏](12-book-ending/05-book-end-toolbars.png) | 读完页面 → 上滑 | 读完状态保留，上下工具栏覆盖于页面。 |

### 13-reading-preferences · 全局阅读偏好

返回书架 → 底部“我” → 设置。首轮仅查看；补拍的开关测试及恢复见15-supplement。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-profile-entry.png · 设置所在页面](13-reading-preferences/01-profile-entry.png) | 书架 → 我 | 个人页的设置入口。 |
| [02-settings.png · 全局设置首页](13-reading-preferences/02-settings.png) | 我 → 设置 | 左侧翻到下一页、正文首行缩进关闭；阅读时显示时间开启。 |
| [03-interface-font-size.png · 界面字号](13-reading-preferences/03-interface-font-size.png) | 设置 → 字体大小 | 明确区分界面字号和正文设置；当前默认，未调整。 |
| [04-settings-last-page.png · 设置最后一页](13-reading-preferences/04-settings-last-page.png) | 设置 → 下一页 | 缓存、隐私、反馈和退出登录入口；未触发这些动作。 |

### 14-community · 书评、热门划线与书友想法

补充样本《正念的奇迹》正文顶部“书友想法”气泡入口，或读完页的推荐值卡片。《蘋果之道》的工具栏没有这组社区入口。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [05-book-reviews-all.png · 全部书评](14-community/05-book-reviews-all.png) | 读完页面 → 推荐值卡片 → 全部 | 推荐值分布与书评卡片列表。 |
| [06-reviews-recommended.png · 推荐书评](14-community/06-reviews-recommended.png) | 书评 → 推荐 | 筛选状态黑底反白。 |
| [07-reviews-average.png · 一般书评](14-community/07-reviews-average.png) | 书评 → 一般 | 筛选后的列表。 |
| [08-reviews-negative.png · 不行书评](14-community/08-reviews-negative.png) | 书评 → 不行 | 筛选后的列表。 |
| [09-review-detail.png · 书评详情](14-community/09-review-detail.png) | 书评列表 → 点击正文 | 全屏书评，底部有赞入口；未点赞或评论。 |
| [11-community-popover.png · 读完页社区入口](14-community/11-community-popover.png) | 读完页 → 上滑工具栏 → 气泡图标 | 书评1585、热门划线374和显示书友想法入口；数值为采集时快照。 |
| [12-popular-highlights.png · 热门划线列表](14-community/12-popular-highlights.png) | 社区气泡 → 热门划线 | 按章节展示热门片段及划线人数。 |
| [13-popular-highlight-jump.png · 热门划线跳转](14-community/13-popular-highlight-jump.png) | 热门划线列表 → 点击一条片段 | 跳回正文，底部黑条含关闭、上一句、下一句、列表。 |
| [14-community-popover-in-book.png · 正文社区入口](14-community/14-community-popover-in-book.png) | 正文 → 上滑工具栏 → 气泡图标 | 同一组社区概况入口可在正文使用。 |
| [15-show-reader-thoughts.png · 显示书友想法](14-community/15-show-reader-thoughts.png) | 社区气泡 → 显示书友想法 | 正文出现虚线标记，并提示已显示。 |
| [16-reader-thoughts-for-passage.png · 某片段的书友想法](14-community/16-reader-thoughts-for-passage.png) | 点击带虚线的片段 | 上方引用卡，下面多位书友的想法、赞和评论入口。 |
| [17-community-thought-editor.png · 从书友想法进入编辑](14-community/17-community-thought-editor.png) | 片段想法列表 → 写想法 | 引用已带入，编辑器与键盘展开；随后取消，没有发表。 |
| [19-return-to-popular-highlights.png · 返回热门划线列表](14-community/19-return-to-popular-highlights.png) | 热门片段黑色导航条 → 右侧列表图标 | 回到热门划线列表。 |
| [20-hide-reader-thoughts-action.png · 隐藏书友想法入口](14-community/20-hide-reader-thoughts-action.png) | 正文 → 社区气泡 | 操作按钮变为“隐藏书友想法”；之后已点击恢复隐藏并核对正文虚线消失。 |

### 15-supplement · 补拍：入口、手势、进度与书末

2026-10-23 16:48–17:14补拍；原图编号续排并允许跳号。长按封面的同帧无障碍XML另见06-book-cover-long-press.xml。

| 原图 | 操作路径 | 画面与备注 |
| --- | --- | --- |
| [01-baseline-reading-no-hint.png · 补拍前原阅读位置](15-supplement/01-baseline-reading-no-hint.png) | 唤醒设备，未重新打开书 | 《蘋果之道》第7章“選單”，87/648；此时没有上滑提示。 |
| [02-import-instructions.png · 导入说明页](15-supplement/02-import-instructions.png) | 书架 → 导入 | 只有“从手机中导入”和“从电脑中导入”两段说明：手机版微信读书书架→导入；电脑r.qq.com→传书到手机。底部X关闭；未实际导入。 |
| [03-selection-mode-empty.png · 选择模式未选中](15-supplement/03-selection-mode-empty.png) | 书架 → 选择 | 顶栏全选、选择书籍、取消；封面空圆圈；底部动作在零选中时禁用。 |
| [04-two-books-selected.png · 选中两本书](15-supplement/04-two-books-selected.png) | 选择模式 → 点两本封面 | 粗黑边框、勾选圆圈，标题已选择2本书籍；下载灰色，移出书架与私密动作可见；未执行动作。 |
| [05-all-books-selected.png · 全选385本](15-supplement/05-all-books-selected.png) | 选择模式 → 全选 | 已选择385本书籍；全选变“取消全选”，作用于整架；底部下载、移出书架、私密动作，均未执行。 |
| [06-book-cover-long-press.png · 长按封面进入选择](15-supplement/06-book-cover-long-press.png) | 普通书架 → 长按《蘋果之道》封面 | 直接进入选择模式并选中1本，没有独立封面菜单。同帧XML将左下面具角标标为“私密阅读”，底栏为“关闭私密阅读”；本书单选时该动作禁用，未切换。 |
| [07-home-search-entry.png · 首页搜索输入页](15-supplement/07-home-search-entry.png) | 书架 → 顶部搜索框 | 独立搜索页，上部推荐词，下部搜索历史；原有历史从PARC开始。 |
| [08-home-search-query.png · 输入审判](15-supplement/08-home-search-query.png) | 搜索页 → 输入书架已有书名“审判” | 原生键盘展开，输入尚未提交；未购买或添加书籍。 |
| [09-home-search-results.png · 书架与书城搜索结果](15-supplement/09-home-search-results.png) | 提交“审判” | 按“在书架中搜索：审判”和“在书城中搜索：审判”分段；书架匹配在前，书城下有电子书、版本、推荐值及在读人数。 |
| [10-open-book-toolbar-hint.png · 打开书后上滑提示](15-supplement/10-open-book-toolbar-hint.png) | 搜索结果 → 点击书架内《审判》 → 约3秒 | 26/296，底部出现“↑ 上滑显示工具栏”；是已有阅读进度，并非首次读这本书。 |
| [11-hint-after-next-page.png · 提示消失后翻页](15-supplement/11-hint-after-next-page.png) | 打开书后静置65秒 → 点击右侧 | 27/296，没有再次出现提示；不是每次翻页都展示。 |
| [12-hint-disappeared-after-65-seconds.png · 静置65秒后提示消失](15-supplement/12-hint-disappeared-after-65-seconds.png) | 从10静置65秒，期间未操作 | 仍是26/296原段落，提示已消失。仅确定65秒内消失，未测精确超时阈值。 |
| [13-progress-before-jump.png · 跳转前进度](15-supplement/13-progress-before-jump.png) | 《审判》原26页 → 上滑 → 进度 | 8%、14条笔记；记录跳转起点。 |
| [14-progress-after-drag-jump.png · 拖动跳转后的返回入口](15-supplement/14-progress-after-drag-jump.png) | 进度滑块从原位置拖至中间 → 松手 | 跳到51%附近，正文上浮出“‹ 返回原进度”胶囊，轨道保留灰点。没有把普通轨道点击当作灰点返回证据。 |
| [17-return-original-progress-result.png · 返回原进度结果](15-supplement/17-return-original-progress-result.png) | 中途数次轨道跳转后 → 返回原进度 | 返回与13相同的26页正文，并自动收起面板/工具栏；总页数重算为289。 |
| [18-drag-unfinished-book-to-end.png · 未读完书拖至100%](15-supplement/18-drag-unfinished-book-to-end.png) | 恢复《审判》26页 → 进度 → 拖至最右端 | 面板100%，拖动期间正文仍是原页；尚未显示读完页。 |
| [19-unfinished-book-end-result.png · 100%跳转完成](15-supplement/19-unfinished-book-end-result.png) | 18松手 → 等待加载 | 到译后记尾页；进度面板保留，“返回原进度”可见。 |
| [20-last-page-before-finish.png · 真正的最后正文页](15-supplement/20-last-page-before-finish.png) | 关闭进度面板 | 296/296，译后记末尾，尚未显示全书完；返回原进度胶囊仍在。 |
| [21-finish-page-mark-button.png · 未读完书的全书完页面](15-supplement/21-finish-page-mark-button.png) | 最后正文页 → 再点右侧翻页 | “全书完”、完字徽章、下划线“标记读完”、本书统计与推荐值、退出阅读；未点击标记读完。 |
| [22-unfinished-book-position-restored.png · 书末测试返回原位置](15-supplement/22-unfinished-book-position-restored.png) | 全书完页 → 返回原进度 | 回到《审判》原26页正文；未标记读完。 |
| [23-left-side-next-enabled.png · 左侧下一页开关开启](15-supplement/23-left-side-next-enabled.png) | 我 → 设置 → 点击左侧翻到下一页 | 开关黑底、圆点在右；其他阅读开关保持原值。 |
| [24-shelf-before-gesture-tests.png · 未读完状态保留](15-supplement/24-shelf-before-gesture-tests.png) | 退出设置 → 书架 | 《审判》没有读完角标，《正念的奇迹》仍有；未执行标记读完。 |
| [25-left-next-test-baseline.png · 翻页测试起点](15-supplement/25-left-next-test-baseline.png) | 开关开启后 → 打开《蘋果之道》 | 原正文87/648；重新进入阅读时再次出现上滑提示。 |
| [26-enabled-left-tap-next.png · 开启后点击左侧](15-supplement/26-enabled-left-tap-next.png) | 25 → 点击左侧x70,y800 | 从87到88，左侧也是下一页。 |
| [27-enabled-right-tap-next.png · 开启后点击右侧](15-supplement/27-enabled-right-tap-next.png) | 26 → 点击右侧x1190,y800 | 从88到89，右侧仍是下一页；不是左右交换。 |
| [28-left-side-next-restored-off.png · 翻页开关恢复关闭](15-supplement/28-left-side-next-restored-off.png) | 退出阅读 → 我 → 设置 → 关闭该开关 | 白底描边、圆点在左；首行缩进仍关、阅读时间仍开。 |
| [29-default-left-taps-position-restored.png · 默认左侧翻回原位置](15-supplement/29-default-left-taps-position-restored.png) | 开关关闭 → 重新打开书 → 左侧点两次 | 89→88→87，恢复原正文；左侧重新是上一页。 |
| [30-direct-hold-drag-released.png · 连续长按拖动松手](15-supplement/30-direct-hold-drag-released.png) | 在原本无划线的PARC处按住1秒，不松手向右拖动 → 松手 | 范围扩为“PARC 的 Smalltalk 程式”，自动出现实线；第一项已经是“删除划线”，未点菜单“划线”。 |
| [31-direct-drag-note-count.png · 连续拖动后笔记43条](15-supplement/31-direct-drag-note-count.png) | 关闭选中菜单 → 打开进度 | 42→43，证明这次扩选已持久保存，非临时选区。 |
| [32-direct-drag-test-highlight-deleted.png · 第一条测试划线删除](15-supplement/32-direct-drag-test-highlight-deleted.png) | 点刚生成的划线 → 删除划线 | 该范围下划线消失，再进行第二种手势。 |
| [33-long-press-release-word-handles.png · 长按松手后的词和手柄](15-supplement/33-long-press-release-word-handles.png) | 长按PARC约900ms → 松手 | 仅单词选中，显示两端黑手柄；菜单仍为“划线”，尚未自动保存。 |
| [34-handle-drag-released.png · 松手后拖手柄扩选](15-supplement/34-handle-drag-released.png) | 33 → 拖右手柄至后续行 → 松手 | 跨行范围自动出现实线；菜单变“删除划线”，没有点击“划线”。 |
| [35-handle-drag-note-count.png · 手柄扩选后笔记43条](15-supplement/35-handle-drag-note-count.png) | 关闭菜单 → 打开进度 | 再次42→43；这条跨行扩选也已保存。 |
| [36-handle-drag-highlight-delete-menu.png · 第二条测试划线删除入口](15-supplement/36-handle-drag-highlight-delete-menu.png) | 关闭进度 → 点本次跨行划线 | 确认菜单为删除划线，只针对刚生成的测试范围。 |
| [37-handle-drag-test-highlight-deleted.png · 第二条测试划线删除](15-supplement/37-handle-drag-test-highlight-deleted.png) | 36 → 删除划线 | 本次跨行范围下划线消失；原有其他笔记未动。 |
| [38-notes-restored-42.png · 笔记数恢复42条](15-supplement/38-notes-restored-42.png) | 删除第二条测试划线 → 打开进度 | 与补拍前42条一致，自动翻页仍关闭。 |
| [39-footnote-search-toc.png · 查找脚注的目录](15-supplement/39-footnote-search-toc.png) | 《蘋果之道》 → 目录 | 目录中可前往“注释”；目录本身不能证明存在脚注弹层。 |
| [40-apple-endnotes-chapter.png · 注释是普通正文页](15-supplement/40-apple-endnotes-chapter.png) | 目录尾部 → 注释 → 等待加载 | “注释”以章节正文展示，含下载链接、缩写、来源资料；未找到正文脚注标记，不是脚注弹层。 |
| [41-apple-original-body-restored.png · 查注释后原正文恢复](15-supplement/41-apple-original-body-restored.png) | 全文搜索Smalltalk → 命中原段落 → 关闭搜索导航 | 恢复第7章“選單”的原文字和插图；重排后77/581，与01原内容相同。 |
| [42-trial-final-position-restored.png · 审判最终位置恢复](15-supplement/42-trial-final-position-restored.png) | 抽查《审判》26–29页找脚注 → 左翻三页 | 恢复26/296原段落；抽查页未见可点击脚注标记。 |
| [43-search-history-cleanup-limit.png · 搜索历史清理限制](15-supplement/43-search-history-cleanup-limit.png) | 返回首页搜索 → 清空输入 → 收起键盘 | 新增“审判”历史仍在，界面仅有“清空”；长按/横滑未找到单条删除。为保留原有历史未执行清空，不声称测试痕迹全部回滚。 |
| [44-final-reading-restored.png · 补拍完成原阅读位置](15-supplement/44-final-reading-restored.png) | 退出搜索 → 重新打开《蘋果之道》 | 恢复“選單”原文字与插图，77/581；没有测试划线、搜索导航或后台播放器。重新进入后临时上滑提示再次出现。 |

