# 微信读书 Leaf5 实机走查与当前 fork 的需求差异清单

整理日期：2026-10-23。代码基线：`6d68579488bd619ec870f2ceb65ea94cdd509812`（本地当前HEAD，含已合并PR #27）。本文件只记录需求与差异，不改代码、DESIGN/CONTEXT/demo，也不创建或修改 issue。

证据范围为本目录的 **185张原始截图、16个截图目录（首轮143张＋本轮补拍42张）**，连同书架/个人页入口。主样本《蘋果之道》，社区补充样本《正念的奇迹》，未读完书末补充样本《审判（果麦经典）》；应用为微信读书墨水屏版2.1.2，BOOX Leaf5竖屏1264×1680。操作顺序和恢复记录见[采集索引](README.md)，原图可在[离线图库](index.html)浏览。

当前实现判断以已合并Lua及插件代码为准；原型表示设计，历史issue表示当时约定，二者都不自动等于当前运行效果。本轮没有重新安装/运行这个fork或做逐像素对图，故代码中的布局、入口和能力可以确认，真机比例、字体渲染、刷新和残影仍须单独验收。

## 标签与读法

- **[可做]**：现有KOReader引擎/数据/插件或通用绘制能力能承接该本地交互，主要是保留、接入、改布局或补状态。包含已具备需保留的项，不表示每条都是尚未开发的功能，也不表示已经视觉验收。
- **[微信读书独有]**：目标动作依赖微信账号、书城授权、云音色或跨读者社区等服务，当前fork没有对应后端。记录以划清范围，不制作假按钮、假数据或假公开发表。
- **[待定]**：缺实测证据、需要新增/核实后端，或与已合并本地能力发生布局/语义冲突；每条说明具体原因。待定不等于做不到。

每条均列出微信读书表现及截图、当前fork事实、差异与落点。截图链接同时标明目录和文件名；输入、加载、完成、删除确认等中间态会合并成一个功能需求，不把每张截图机械计为一项。本轮补拍已确认的导入、多选、首页搜索、角标、提示、进度返回、翻页、扩选和未读完书末行为见15-supplement；未找到的脚注弹层、真实笔输入等不补造细节。

## 历史约定与已合并基线

| 历史issue | 核对结论 |
| --- | --- |
| [#1 总改版](https://github.com/justinyanme/koreader/issues/1)（OPEN） | 最初约定四格底栏、黑气泡、目录抽屉，听书范围外；评论确认#3–#12已合并，也列出截图校准与真机待验收。后来的Note X6试用记录不等于Leaf5上这些新差异已验收。 |
| [#3 基础](https://github.com/justinyanme/koreader/issues/3)（CLOSED） | 后续评论修订为生产纯白/纯黑、灰度常量、字体角色及替换挂钩；不能按issue最初Size表方案或demo米白判断生产现状。 |
| [#4 工具栏](https://github.com/justinyanme/koreader/issues/4)（CLOSED） | 工具栏/进度/亮度/更多已合并；评论明确面板打开隐藏工具栏、书签沿用上游折角，都是本轮要对照的已知差异。 |
| [#5 排版](https://github.com/justinyanme/koreader/issues/5)（CLOSED） | 主面板与更多、页眉章节已合并；评论说明原样式微调回退、dp/边距映射及用户设置不覆盖。 |
| [#6 划线](https://github.com/justinyanme/koreader/issues/6)（CLOSED） | 三样式、气泡、想法已合并；评论明确生产沿用灰色选区，与demo反白不同。波浪线等历史约定不因新样本未出现而自动删除。 |
| [#7 查词](https://github.com/justinyanme/koreader/issues/7)（CLOSED） | 本地词典/Wikipedia面板、生词本及全文搜索能力已实现，当前布局需对照全屏查询卡片。 |
| [#8 目录](https://github.com/justinyanme/koreader/issues/8)（CLOSED） | 侧抽屉、三个tabs、平铺层级和导出已实现，与实机全屏目录及统一笔记页不同。 |
| [#9 书架](https://github.com/justinyanme/koreader/issues/9)（CLOSED） | 递归主目录、状态筛选、搜索、排序及三标签已实现；评论明确书架批量管理暂不做、搜索原地过滤和真实满库耗时仍待验收。 |
| [#10 文件](https://github.com/justinyanme/koreader/issues/10)（CLOSED） | 文件页沿用FileChooser能力，重绘面包屑/行/更多；不是微信云书架的替代数据源。 |
| [#11 我的](https://github.com/justinyanme/koreader/issues/11)（CLOSED） | 本地统计/全局笔记/生词本/传书已实现；子页保留底栏是已接受的原型差异。 |
| [#12 设置](https://github.com/justinyanme/koreader/issues/12)（CLOSED） | 五组入口及原版回退已合并；微信简短偏好列表不能替代KOReader全部设置。 |
| [#24 书源](https://github.com/justinyanme/koreader/issues/24)（CLOSED） | 已合并新书源UI；后续PR #27修正首页与下载行为。当前下载完成只标记、不自动打开，以BookSourceView.finishDownload代码为准；#24早期方案、历史验收文字和demo若仍写自动打开，均不代表现状。 |

规范与原型：[DESIGN.md](../../../DESIGN.md)、[CONTEXT.md](../../../CONTEXT.md)、[design/demo/index.html](../../demo/index.html)。需求出现冲突时，在本清单中登记，不把历史“已完成”翻译成“没有差异”。

## 分组统计

共 **20组、136项**：**[可做] 85项、[微信读书独有] 15项、[待定] 36项**。按需求条目计数，不是工时或待开issue数量。

| 分组 | 可做 | 微信读书独有 | 待定 | 合计 |
| --- | ---: | ---: | ---: | ---: |
| A. 书架、首页与打开入口（00-entry） | 8 | 2 | 1 | 11 |
| B. 阅读页、翻页与位置（01-reader-navigation） | 6 | 0 | 0 | 6 |
| C. 阅读工具栏与书籍条件入口（01、10） | 3 | 0 | 2 | 5 |
| D. 排版、字体与段落（02-typography） | 9 | 0 | 1 | 10 |
| E. 阅读进度与统计（03-progress） | 5 | 0 | 1 | 6 |
| F. 自动翻页与划线导读（03-progress） | 2 | 0 | 2 | 4 |
| G. 全屏目录与全文搜索（04-contents-and-search） | 8 | 0 | 0 | 8 |
| H. 书签（05-bookmarks） | 5 | 0 | 0 | 5 |
| I. 笔记列表、计数与空状态（06-notes） | 7 | 0 | 0 | 7 |
| J. 写想法、私密状态与自己的想法详情（07） | 3 | 1 | 2 | 6 |
| K. 文字选择与划线菜单（07-selection-and-lookup） | 7 | 0 | 1 | 8 |
| L. 查词、翻译与百科（07-selection-and-lookup） | 4 | 1 | 2 | 7 |
| M. 听书与后台播放器（08-listening） | 0 | 1 | 8 | 9 |
| N. 图片与脚注（09-images） | 2 | 0 | 2 | 4 |
| O. 繁简转换、书架与下载等书籍操作（10） | 2 | 1 | 2 | 5 |
| P. 手写模式与手写笔记（11-handwriting） | 0 | 0 | 5 | 5 |
| Q. 书末页与读完状态（12-book-ending） | 3 | 1 | 1 | 5 |
| R. 阅读偏好、界面字号与个人页入口（13） | 6 | 0 | 1 | 7 |
| S. 社区、书评与微信账号入口（14-community、13） | 0 | 8 | 0 | 8 |
| T. 共用视觉、证据边界与已有能力的保留（横跨16目录） | 5 | 0 | 5 | 10 |
| **总计** | **85** | **15** | **36** | **136** |

## 本轮补拍与标签修订

新增[15-supplement](15-supplement/)42张原图，原143张未改。9项从待定转出：**可做7项（A08、A09、B05、E05、K08、Q02、R02）**，**微信读书独有2项（A06、A11）**。A04/A05/A07、K04、Q01、B06同步修正说明；需求ID与总数保持不变。

N04仍待定：查到的“注释”是普通章节，未找到脚注弹层。E05采用已实测的“返回原进度”按钮路径，灰点自身点击含义未确认；B05只确定进入阅读出现、65秒内消失，没有精确计时阈值。未执行导入、批量动作、隐私切换或标记读完。

## 先处理的规范冲突

这些是同一需求跨文档与实现的差异，不能只改一张原型图：全屏目录/统一笔记与三tabs侧抽屉；六位置底栏与四入口；白底图标选词菜单与黑底纯文字菜单；四行排版轨道/字体网格与三段选择/两张字体卡；正文面板保留工具栏与打开sheet隐藏工具栏；笔记包含书签与CONTEXT排除书签。对应条目为G01/H02/I01、C01、K01/K03、D01–D06、C04/T02、T06。

## 逐项需求

## A. 书架、首页与打开入口（00-entry）

当前代码落点：[`frontend/apps/shelf/shelfview.lua`](../../../frontend/apps/shelf/shelfview.lua)、[`frontend/apps/shelf/shelfwidgets.lua`](../../../frontend/apps/shelf/shelfwidgets.lua)、[`frontend/apps/shelf/shelf.lua`](../../../frontend/apps/shelf/shelf.lua)、[`frontend/apps/shelf/shelffilemanager.lua`](../../../frontend/apps/shelf/shelffilemanager.lua)、[`frontend/apps/opds/booksourceview.lua`](../../../frontend/apps/opds/booksourceview.lua)。

### A01 [可做] 书架首页的信息层级

- **微信读书**：上方是整行圆角搜索框，下一行左侧大标题“书架”，右侧“导入”“选择”，下面才是封面网格。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`08-listening/25-mini-player-closed.png`](08-listening/25-mini-player-closed.png)。
- **当前fork**：ShelfView.buildHeader 把搜索、书源和排序放同一行，下一行是全部/在读/未读/读完筛选 chips，没有独立“书架”标题行。
- **差异 / 要求**：改造主布局为截图层级；已有筛选与排序的后续位置见 A10，不能误认为截图里也有这排筛选。

### A02 [可做] Leaf5 的封面网格与书名

- **微信读书**：本机为4列；封面下单行粗书名省略显示，纵向保留较大的封面面积。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)。
- **当前fork**：gridGeometry 按屏幕宽度/DPI决定3/4/5列，1264px、300DPI落在4列档；buildCell 为最多两行标题和另起一行状态，封面固定3:4裁切。
- **差异 / 要求**：4列能力已有；校准标题字重、单行截断、封面比例、行距和可见行数。截图不能证明所有书都强制裁切为3:4，需以对应原封面核对。

### A03 [可做] 本地/已下载与读完的视觉标记

- **微信读书**：标题前有圆形勾；“读完”是封面右上角黑字白底角标。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`08-listening/25-mini-player-closed.png`](08-listening/25-mini-player-closed.png)。
- **当前fork**：本地书架状态通过封面下第二行显示；书源网格已在标题前画已下载勾。
- **差异 / 要求**：复用书源已有下载标记的画法，统一两处；读完状态移到封面角标，避免只有文本状态而没有角标。

### A04 [可做] 打开书籍与最近阅读排序

- **微信读书**：点封面进入正文，重新打开保留位置；最近打开的书会移到前面。长按封面直接进入选择模式并选中该书，没有独立封面菜单。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`00-entry/02-book-open.png`](00-entry/02-book-open.png)、[`00-entry/03-final-reading-position.png`](00-entry/03-final-reading-position.png)、[`15-supplement/06-book-cover-long-press.png`](15-supplement/06-book-cover-long-press.png)。
- **当前fork**：Shelf.scan/load/view已按最近阅读及未读文件mtime排序，openBook调用正常阅读入口；书架长按仍用现有本地书籍操作。
- **差异 / 要求**：保留点击打开与位置；如采用同款批量选择，长按接入A08，不额外发明微信读书封面菜单。本地书籍操作仍须另有可达入口。

### A05 [可做] 本地导入的可见入口

- **微信读书**：标题行“+ 导入”打开两段跨设备传书说明，不是本机文件选择器，实际内容见A06。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`15-supplement/02-import-instructions.png`](15-supplement/02-import-instructions.png)。
- **当前fork**：主目录递归扫描本地书；文件页、无线传书、Calibre、云存储和书源可取得文件，书架没有“导入”文字入口。
- **差异 / 要求**：显式入口和说明页视觉可用现有本地传书能力实现；文案链接应指向KOReader真实路径。截图未验证文件复制/移动、格式或去重规则，不据此规定本地导入细节。

### A06 [微信读书独有] 导入页的微信跨设备传书流程

- **微信读书**：点导入后是全屏两段说明：“从手机中导入”要求手机版微信读书→书架→导入；“从电脑中导入”要求r.qq.com→传书到手机；图示居中，底部圆形X关闭。没有本机选文件菜单，未实际导入。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`15-supplement/02-import-instructions.png`](15-supplement/02-import-instructions.png)。
- **当前fork**：本地书架与现有传书/文件选择器不连接微信读书账号、r.qq.com或其云书架。
- **差异 / 要求**：这两条具体服务流程依赖微信读书，应排除复刻；本地替代入口见A05。只查看说明不意味着已验证账号同步、格式、去重或上传结果。

### A07 [可做] 书架批量选择入口

- **微信读书**：标题右侧“选择”进入空选择模式；长按封面则直接进入并选中该书，顶栏均可取消退出。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`15-supplement/03-selection-mode-empty.png`](15-supplement/03-selection-mode-empty.png)、[`15-supplement/06-book-cover-long-press.png`](15-supplement/06-book-cover-long-press.png)。
- **当前fork**：#9明确暂不做书架批量管理；原FileChooser有选择模式，ShelfView没有对应模式。
- **差异 / 要求**：复用本地多选能力，补显式入口与长按进入路径；状态、整架全选及底部动作见A08。现有本地书籍操作另保留入口。

### A08 [可做] 多选状态、全选及底部动作

- **微信读书**：零选中时标题“选择书籍”，封面空圈、底部禁用；选中后粗黑框/实心勾和“已选择N本书籍”；全选选中整架385本并变“取消全选”，右上“取消”退出。底部为下载、移出书架、私密动作，随选中对象启用/禁用；这轮未执行任何底部动作。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`15-supplement/03-selection-mode-empty.png`](15-supplement/03-selection-mode-empty.png)、[`15-supplement/04-two-books-selected.png`](15-supplement/04-two-books-selected.png)、[`15-supplement/05-all-books-selected.png`](15-supplement/05-all-books-selected.png)、[`15-supplement/06-book-cover-long-press.png`](15-supplement/06-book-cover-long-press.png)。
- **当前fork**：文件页已有多选与批量文件操作，书架未接入；本地删除文件、隐藏书架与云端移出书架不是同一个动作。
- **差异 / 要求**：可做本地选择/计数/全选/取消和真实本地批量动作。全选范围须明确，不只勾当前页；不可用文件删除直接代替移出书架。云下载/账号私密需对应后端，私密见A11；本轮未验证动作后的确认层或执行结果。

### A09 [可做] 首页搜索输入页及分区结果

- **微信读书**：点首页搜索框进入独立页：上方搜索框和推荐词，下方历史及“清空”；输入“审判”提交后，先列“在书架中搜索：审判”，后列“在书城中搜索：审判”与电子书结果。前者是本书架匹配，后者含不同版本、推荐值及在读人数。未找到历史单条删除，测试词尚留存。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`07-selection-and-lookup/03-selected-text-bookstore-search.png`](07-selection-and-lookup/03-selected-text-bookstore-search.png)、[`15-supplement/07-home-search-entry.png`](15-supplement/07-home-search-entry.png)、[`15-supplement/08-home-search-query.png`](15-supplement/08-home-search-query.png)、[`15-supplement/09-home-search-results.png`](15-supplement/09-home-search-results.png)、[`15-supplement/43-search-history-cleanup-limit.png`](15-supplement/43-search-history-cleanup-limit.png)。
- **当前fork**：ShelfView.showSearch仍用输入弹窗后原地过滤本地书名/作者；demo.renderSearch是搜索子页面。本地搜索能力已有，微信书城不属于当前后端。
- **差异 / 要求**：可做独立本地搜索页、历史、结果列表与清晰来源标题，替换原地过滤；推荐词/微信书城内容见L06独有，不能造云结果。搜索来源切换与无结果应真实反馈；清理历史需避免误清原记录。

### A10 [待定] 筛选、排序及底部导航的保留位置

- **微信读书**：拍到的底栏为发现类图标、书架、个人页；没有“文件”标签和书架筛选 chips，导入/选择在标题行。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)。
- **当前fork**：当前为书架/文件/我的三标签，书架有四种状态筛选、排序及#24书源入口。
- **差异 / 要求**：这些是已经合并的本地工作流，不能因样本无对应项直接删除。需决定移入二级入口还是保留，以及书源与导入如何共存；不照搬微信发现推荐页。

### A11 [微信读书独有] 面具角标表示账号私密阅读

- **微信读书**：封面左下面具角标的同帧无障碍标签明确是“私密阅读”（book_cover_privacy_icon）；底栏动作标签是“关闭私密阅读”（bottombar_secret）。长按封面进入单选，本书单选该动作灰色，全选可用；未切换。原始标签见[06-book-cover-long-press.xml](15-supplement/06-book-cover-long-press.xml)。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`15-supplement/04-two-books-selected.png`](15-supplement/04-two-books-selected.png)、[`15-supplement/05-all-books-selected.png`](15-supplement/05-all-books-selected.png)、[`15-supplement/06-book-cover-long-press.png`](15-supplement/06-book-cover-long-press.png)。
- **当前fork**：本地书仅有状态、文件与书源下载记录，没有向微信好友/账号公开阅读动态的系统。
- **差异 / 要求**：角标语义已确认，表示微信账号的阅读隐私，当前fork无此服务，不复制假隐私开关，也不借面具表示本地下载。尚未验证哪些书可切换及其云端传播规则，不作额外推断。

## B. 阅读页、翻页与位置（01-reader-navigation）

当前代码落点：[`frontend/apps/reader/modules/readertoolbar.lua`](../../../frontend/apps/reader/modules/readertoolbar.lua)、[`frontend/apps/reader/modules/readerchapterheader.lua`](../../../frontend/apps/reader/modules/readerchapterheader.lua)、[`frontend/apps/reader/modules/readerfooter.lua`](../../../frontend/apps/reader/modules/readerfooter.lua)、[`frontend/apps/reader/modules/readerhighlight.lua`](../../../frontend/apps/reader/modules/readerhighlight.lua)、[`frontend/apps/reader/modules/readerlink.lua`](../../../frontend/apps/reader/modules/readerlink.lua)。

### B01 [可做] 正文优先与章节页眉

- **微信读书**：普通阅读时隐藏操作栏，左上章节文字，正文占据主要面积。 证据：[`00-entry/02-book-open.png`](00-entry/02-book-open.png)、[`00-entry/03-final-reading-position.png`](00-entry/03-final-reading-position.png)。
- **当前fork**：ReaderChapterHeader 已绘制章节名，无目录时用书名；正文仍由原引擎排版，部分模式不画自定义页眉。
- **差异 / 要求**：主体方向已具备；对齐截图中的章节字体、左边距和垂直留白。保留上边距不足、滚动模式、版式书的既有防重叠处理，不强套截图排版。

### B02 [可做] 页脚时间与全书页码

- **微信读书**：左下时间，右下当前页/总页数；补录画面中间有“上滑显示工具栏”提示。 证据：[`00-entry/02-book-open.png`](00-entry/02-book-open.png)、[`00-entry/03-final-reading-position.png`](00-entry/03-final-reading-position.png)。
- **当前fork**：applyFooterDefaults 默认组合为本章页码、全书百分比、时间、电量，关闭进度条；不是截图的两端布局。
- **差异 / 要求**：保留用户自定义的前提下校准新默认布局；提供全书页码形式。提示文字的显示条件单列 B05，不能把一次提示永久写进页脚。

### B03 [可做] 左右点击与横向滑动翻页

- **微信读书**：点击左右区域及横滑均能翻页，正文不常驻操作控件。 证据：[`01-reader-navigation/02-tap-next-page.png`](01-reader-navigation/02-tap-next-page.png)、[`01-reader-navigation/03-tap-previous-page.png`](01-reader-navigation/03-tap-previous-page.png)、[`01-reader-navigation/04-swipe-next-page.png`](01-reader-navigation/04-swipe-next-page.png)。
- **当前fork**：getTapLayout/onTapPage 已有默认三分区，并沿用翻页模块的滑动与实体键。
- **差异 / 要求**：保持能力，校准事件优先级，图片、链接、已有划线点击应先处理；截图没有证明左右热区恰好各占三分之一，不把该比例作为实测值。

### B04 [可做] 上滑唤出、点击收起工具栏

- **微信读书**：上滑明确出现上下工具栏，阅读页有对应提示；操作完成可回无栏正文。 证据：[`01-reader-navigation/01-toolbars.png`](01-reader-navigation/01-toolbars.png)、[`01-reader-navigation/05-swipe-up-toolbars.png`](01-reader-navigation/05-swipe-up-toolbars.png)。
- **当前fork**：ReaderToolbar 注册整页 tap；继承菜单及系统手势可能也可唤出，但新模块未专门定义等同样本的上滑路径。
- **差异 / 要求**：补齐明确且可配置的上滑入口，验证与滚动阅读、原手势插件无冲突；收起只退出工具栏状态，不能误翻页或丢阅读位置。

### B05 [可做] 重新进入阅读的临时上滑提示

- **微信读书**：唤醒停留原书时无提示；从本地搜索打开已有进度的《审判》，以及从书架重开《蘋果之道》，底部中间出现灰色“↑ 上滑显示工具栏”。原页静置65秒后提示消失，随后下一页不重现；重开书又出现。 证据：[`00-entry/03-final-reading-position.png`](00-entry/03-final-reading-position.png)、[`15-supplement/01-baseline-reading-no-hint.png`](15-supplement/01-baseline-reading-no-hint.png)、[`15-supplement/10-open-book-toolbar-hint.png`](15-supplement/10-open-book-toolbar-hint.png)、[`15-supplement/11-hint-after-next-page.png`](15-supplement/11-hint-after-next-page.png)、[`15-supplement/12-hint-disappeared-after-65-seconds.png`](15-supplement/12-hint-disappeared-after-65-seconds.png)、[`15-supplement/25-left-next-test-baseline.png`](15-supplement/25-left-next-test-baseline.png)、[`15-supplement/44-final-reading-restored.png`](15-supplement/44-final-reading-restored.png)。
- **当前fork**：当前新页脚没有这条教学提示；已有工具栏、页脚绘制及UI定时能力可承接，明确上滑入口仍需按B04接入。
- **差异 / 要求**：可实现进入阅读时短暂展示、随后隐藏的教学提示，不占常驻页脚也不每页重放。这里只测得65秒内消失，精确超时/更多条件未测，不写成固定65秒；KOReader实现需统一提示生命周期。

### B06 [可做] 重排与跳转后的稳定位置

- **微信读书**：相同原文段落在不同阶段显示不同总页数；调整字体或下载后会重新分页。 补拍恢复同段文字/插图后，《蘋果之道》页码从87/648重算为77/581，《审判》恢复26/296；按内容核对，非按总页数判定。 证据：[`00-entry/02-book-open.png`](00-entry/02-book-open.png)、[`00-entry/03-final-reading-position.png`](00-entry/03-final-reading-position.png)、[`02-typography/14-original-settings-restored.png`](02-typography/14-original-settings-restored.png)、[`02-typography/15-paragraph-settings-restored.png`](02-typography/15-paragraph-settings-restored.png)、[`15-supplement/41-apple-original-body-restored.png`](15-supplement/41-apple-original-body-restored.png)、[`15-supplement/42-trial-final-position-restored.png`](15-supplement/42-trial-final-position-restored.png)、[`15-supplement/44-final-reading-restored.png`](15-supplement/44-final-reading-restored.png)。
- **当前fork**：流式书使用XPointer等稳定位置，版式书按页；新排版面板调用原排版事件。
- **差异 / 要求**：以正文锚点和内容恢复验收，重排期间更新页数/百分比时避免旧值误导；不要求把微信读书的具体页码算法复制过来。

## C. 阅读工具栏与书籍条件入口（01、10）

当前代码落点：[`frontend/apps/reader/modules/readertoolbar.lua`](../../../frontend/apps/reader/modules/readertoolbar.lua)、[`frontend/apps/reader/modules/readertoolbarpanels.lua`](../../../frontend/apps/reader/modules/readertoolbarpanels.lua)、[`frontend/ui/widget/bottomsheet.lua`](../../../frontend/ui/widget/bottomsheet.lua)。

### C01 [可做] 底部入口结构与直接笔记入口

- **微信读书**：底部从左到右是返回、目录、笔记、进度、A、听书，前五项主要用独立图标，末项“听”；截图没有亮度按钮。 证据：[`01-reader-navigation/01-toolbars.png`](01-reader-navigation/01-toolbars.png)、[`01-reader-navigation/05-swipe-up-toolbars.png`](01-reader-navigation/05-swipe-up-toolbars.png)。
- **当前fork**：buildBars 是目录/进度/亮度/字体四格，图标下附文字；返回在顶栏，笔记只能通过目录抽屉页签。
- **差异 / 要求**：可做部分重排为返回、目录、直接笔记、进度、字体；校准图标、间距、分隔和文字。听书缺少后端及空位策略见 M01/C03，不能仅补一个无效“听”按钮。

### C02 [可做] 顶部的本地书籍动作

- **微信读书**：右侧排列繁简、书签、手写、书架、下载等动作，左侧留大块空白；没有当前fork的搜索和“更多”组合。 证据：[`01-reader-navigation/01-toolbars.png`](01-reader-navigation/01-toolbars.png)、[`10-conversion-and-book-actions/03-bookshelf-action.png`](10-conversion-and-book-actions/03-bookshelf-action.png)、[`10-conversion-and-book-actions/04-offline-download-action.png`](10-conversion-and-book-actions/04-offline-download-action.png)。
- **当前fork**：当前顶栏左返回，右书签、搜索、更多。
- **差异 / 要求**：把已有书签、书架动作按截图重排；搜索可移目录页，低频能力保留可达入口。繁简、手写、下载必须按各自能力条件处理，不把所有图标无条件画齐。

### C03 [待定] 按书籍/能力变化的完整顶栏策略

- **微信读书**：两本书顶栏不同：《蘋果之道》有繁简入口，《正念的奇迹》有社区气泡；读完页还会隐藏书签。 证据：[`01-reader-navigation/01-toolbars.png`](01-reader-navigation/01-toolbars.png)、[`14-community/14-community-popover-in-book.png`](14-community/14-community-popover-in-book.png)、[`14-community/11-community-popover.png`](14-community/11-community-popover.png)。
- **当前fork**：buildBars 的按钮组合固定，没有按内容服务能力区分。
- **差异 / 要求**：需要定义本地能力矩阵及排布收缩规则。社区缺失时留白、移除还是替代都未获设计结论；两个样本不足以推断微信读书的全部条件。

### C04 [可做] 工具栏与底部面板同时可见

- **微信读书**：字体或进度面板打开时，底部阅读工具栏继续可见，可直接换功能；上方保留正文。 证据：[`02-typography/01-font-panel.png`](02-typography/01-font-panel.png)、[`03-progress/01-progress-panel.png`](03-progress/01-progress-panel.png)。
- **当前fork**：openPanel/runAction 隐藏工具栏，BottomSheet 自带标题和右上关闭；排版面板是独立sheet。
- **差异 / 要求**：改面板与工具栏的布局/生命周期，允许切换字体、进度、目录、笔记等，不让切换变成先关面板再开栏的额外步骤。

### C05 [待定] 亮度、更多及原版能力的新位置

- **微信读书**：“太阳”形图标实测打开进度，不是亮度；当前采集中没看到“更多”入口。 证据：[`01-reader-navigation/01-toolbars.png`](01-reader-navigation/01-toolbars.png)、[`03-progress/01-progress-panel.png`](03-progress/01-progress-panel.png)。
- **当前fork**：亮度面板已有前光/色温/自动色温/夜间模式，更多包含书籍信息、点击区、导出、统计、设置。
- **差异 / 要求**：不能继续把进度图标误当亮度，也不应删除已实现设备能力。需决定迁到设置、手势或其他可达位置；这属于fork布局决策，截图不提供答案。

## D. 排版、字体与段落（02-typography）

当前代码落点：[`frontend/apps/reader/modules/readertypesetpanel.lua`](../../../frontend/apps/reader/modules/readertypesetpanel.lua)、[`frontend/apps/reader/modules/readerfont.lua`](../../../frontend/apps/reader/modules/readerfont.lua)、[`frontend/apps/reader/modules/readerstyletweak.lua`](../../../frontend/apps/reader/modules/readerstyletweak.lua)、[`frontend/ui/widget/einkcontrols.lua`](../../../frontend/ui/widget/einkcontrols.lua)。

### D01 [可做] 排版主面板的四行结构

- **微信读书**：标题“字体设置”，右上为“首行顶格”胶囊入口；四行依次字号、字重、行距、边距，下面才是字体网格。 证据：[`02-typography/01-font-panel.png`](02-typography/01-font-panel.png)、[`02-typography/14-original-settings-restored.png`](02-typography/14-original-settings-restored.png)。
- **当前fork**：mainContent 为字号、字体三卡、行距三段、边距三段和更多排版；字重藏在moreContent。
- **差异 / 要求**：将四项常用控制放同一屏，字重提升到主面板；段落入口移标题行。高级渲染与原版配置仍需可达，不以主面板精简为由删除。

### D02 [可做] 字号的胶囊轨道与数值圆钮

- **微信读书**：两侧圆形减/加，轨道已选部分黑、未选部分灰；白色描边圆钮直接显示22或24，端点小/大。 证据：[`02-typography/01-font-panel.png`](02-typography/01-font-panel.png)、[`02-typography/02-font-size-increased.png`](02-typography/02-font-size-increased.png)。
- **当前fork**：TickStepper 是A大小按钮、细线刻度和圆点，数值写在外侧标签；只提供固定字号序列。
- **差异 / 要求**：复用SetFontSize与持久化，替换控制外观和数值反馈；上下限与步长按引擎支持校准，不把截图中的22硬设为所有书默认。

### D03 [可做] 字重的直接调节

- **微信读书**：第二行两端细/粗，圆钮显示字重3，可直接加减。 证据：[`02-typography/03-font-weight-increased.png`](02-typography/03-font-weight-increased.png)。
- **当前fork**：moreContent 已使用font_base_weight及SetFontBaseWeight，主屏没有。
- **差异 / 要求**：能力已有，移到主屏并显示当前档位；不将微信读书数字与引擎weight值机械等同，建立可核对映射。

### D04 [可做] 行距和边距的连续档位表达

- **微信读书**：两项也用黑灰胶囊轨道和圆钮，端点紧/松、小/大；正文随修改重排。 证据：[`02-typography/04-line-spacing-increased.png`](02-typography/04-line-spacing-increased.png)、[`02-typography/05-margins-increased.png`](02-typography/05-margins-increased.png)。
- **当前fork**：主面板各只有三段分段按钮，行距105/125/145%，边距18/28/44dp；有额外的行长上限逻辑。
- **差异 / 要求**：引擎可提供更多值，用同一轨道形式展示；保留用户精细值，不强制吸回三档。行长上限是否保留需与目标版心验收，不当成微信读书已有规则。

### D05 [可做] 字体卡片网格与选中态

- **微信读书**：主屏是多列多行字体名称按钮，字体名称自身预览字形；当前名称在上方，选中卡黑底白字，其余灰底。 证据：[`02-typography/01-font-panel.png`](02-typography/01-font-panel.png)、[`02-typography/13-system-font-selected.png`](02-typography/13-system-font-selected.png)。
- **当前fork**：fontCards 只有宋体/黑体/更多三张高卡，展示“永 Aa”加小名称，以加粗边框选中；更多字体跳原菜单。
- **差异 / 要求**：改为多字体名称网格、黑底选中和当前选择文本，复用本地字体枚举与字体切换；不能只改两张卡颜色而缺少列表结构。

### D06 [可做] 展开字体列表及分类导航

- **微信读书**：“查看更多”展开为全部/仓耳/方正/其他标签，附数量，支持切换和收起，仍覆盖于正文下部。 证据：[`02-typography/09-more-fonts.png`](02-typography/09-more-fonts.png)、[`02-typography/10-fonts-canger.png`](02-typography/10-fonts-canger.png)、[`02-typography/11-fonts-founder.png`](02-typography/11-fonts-founder.png)、[`02-typography/12-fonts-other.png`](02-typography/12-fonts-other.png)。
- **当前fork**：现有更多字体直接打开原ReaderFont菜单；有字体列表，但没有同样的网格和分类标签。
- **差异 / 要求**：可用本地已安装字体构建全部及可识别分组，保留展开/收起与当前字体。分类数据必须来自实际字体，不能写死截图里的29/12/7/9。

### D07 [待定] 字体清单、商业字库与系统字体的具体定义

- **微信读书**：样本包含寒蝉、仓耳、方正等字库及系统字体；29种是该设备当时的清单。 证据：[`02-typography/09-more-fonts.png`](02-typography/09-more-fonts.png)、[`02-typography/10-fonts-canger.png`](02-typography/10-fonts-canger.png)、[`02-typography/11-fonts-founder.png`](02-typography/11-fonts-founder.png)、[`02-typography/12-fonts-other.png`](02-typography/12-fonts-other.png)、[`02-typography/13-system-font-selected.png`](02-typography/13-system-font-selected.png)。
- **当前fork**：当前自带Noto系，CJK宋体需用户安装；缺失时提示并回退，按书籍语言选择字体。
- **差异 / 要求**：布局可做，但没有核实字库分发授权、各平台系统字体可用性，以及“系统字体”应映射哪一张字。不能把微信的字库资源作为KOReader已有资产。

### D08 [可做] 首行顶格/缩进的两张大卡

- **微信读书**：段落子面板用两张并排大卡，黑底白字选中，图示与名称并列传达状态。 证据：[`02-typography/06-paragraph-indent.png`](02-typography/06-paragraph-indent.png)、[`02-typography/07-paragraph-indent-selected.png`](02-typography/07-paragraph-indent-selected.png)、[`02-typography/15-paragraph-settings-restored.png`](02-typography/15-paragraph-settings-restored.png)。
- **当前fork**：段首缩进在更多排版里跳原样式微调菜单，已有对应样式能力，无同款子面板。
- **差异 / 要求**：新增便捷子面板，复用排版样式；从现有复杂样式读取不到明确状态时不要谎报已选，保留原版入口。

### D09 [可做] 段间距开关与状态恢复

- **微信读书**：缩进卡内含段间距开关，开启黑底、关闭灰描边；采集后恢复顶格与段间距关闭。 证据：[`02-typography/08-paragraph-spacing-enabled.png`](02-typography/08-paragraph-spacing-enabled.png)、[`02-typography/15-paragraph-settings-restored.png`](02-typography/15-paragraph-settings-restored.png)。
- **当前fork**：段间距同样跳原样式微调菜单，没有该开关。
- **差异 / 要求**：接入既有paragraph_whitespace样式能力并给出读回状态；开关与首行选择是否联动以实测场景为限，不能覆盖用户其他CSS。

### D10 [可做] 即时预览、保持面板及设置持久化

- **微信读书**：调整后面板保持打开，上部正文变化，可连续对照；恢复后能看到原值。 证据：[`02-typography/02-font-size-increased.png`](02-typography/02-font-size-increased.png)、[`02-typography/03-font-weight-increased.png`](02-typography/03-font-weight-increased.png)、[`02-typography/04-line-spacing-increased.png`](02-typography/04-line-spacing-increased.png)、[`02-typography/05-margins-increased.png`](02-typography/05-margins-increased.png)、[`02-typography/14-original-settings-restored.png`](02-typography/14-original-settings-restored.png)。
- **当前fork**：setFontSize/apply/setMarginStep 已经过原排版事件实时重排并保存设置，刷新sheet。
- **差异 / 要求**：保留能力，改新控件后也须保持打开和正确读回；字号、边距联动或重新分页期间不得显示错误的旧档位。

## E. 阅读进度与统计（03-progress）

当前代码落点：[`frontend/apps/reader/modules/readertoolbarpanels.lua`](../../../frontend/apps/reader/modules/readertoolbarpanels.lua)、[`frontend/apps/reader/modules/readerlink.lua`](../../../frontend/apps/reader/modules/readerlink.lua)、[`plugins/statistics.koplugin/main.lua`](../../../plugins/statistics.koplugin/main.lua)、[`frontend/apps/reader/modules/readerannotation.lua`](../../../frontend/apps/reader/modules/readerannotation.lua)。

### E01 [可做] 进度面板的三列统计

- **微信读书**：上方三列分别显示百分比及剩余时长、已读分钟数、笔记条数；下方才是进度轨道。 证据：[`03-progress/01-progress-panel.png`](03-progress/01-progress-panel.png)、[`03-progress/05-progress-panel-after-navigation.png`](03-progress/05-progress-panel-after-navigation.png)。
- **当前fork**：progressContent 显示章节名和本章/全书页码、百分比，没有这组三列；statistics已有当前书阅读时长及页数耗时估计。
- **差异 / 要求**：对接本地统计与annotation计数，改布局。插件关闭或无足够数据时使用明确空值，不能复制演示时长或微信账号统计。

### E02 [可做] 进度面板直接打开笔记

- **微信读书**：点击笔记数进入该书笔记列表；时长列点击本次未见新页面。 证据：[`03-progress/01-progress-panel.png`](03-progress/01-progress-panel.png)、[`06-notes/01-notes-list.png`](06-notes/01-notes-list.png)。
- **当前fork**：新进度面板没有笔记数字和点击入口，已有独立annotation数据与目录抽屉notes页。
- **差异 / 要求**：使数字入口打开新的全屏笔记页并带回当前书；不为时长列凭空新增一个“微信同款”详情页。

### E03 [可做] 进度轨道及两端章节箭头

- **微信读书**：粗胶囊黑灰轨道、白色圆钮，左右端嵌章节箭头；点箭头跳章节。 证据：[`03-progress/01-progress-panel.png`](03-progress/01-progress-panel.png)、[`03-progress/10-tap-progress-track.png`](03-progress/10-tap-progress-track.png)、[`03-progress/11-next-chapter.png`](03-progress/11-next-chapter.png)、[`03-progress/12-previous-chapter.png`](03-progress/12-previous-chapter.png)。
- **当前fork**：ProgressTrack 为细线、章节刻度和空心圆，独立的上一章/下一章文字按钮。
- **差异 / 要求**：复用现有章节跳转，改为轨道两端箭头和截图样式，正确禁用边界箭头；不照搬具体章节标题。

### E04 [可做] 拖动预览、松手跳转与加载反馈

- **微信读书**：按住移动时百分比先变、正文暂留旧位置；松手出现加载，再展示目标正文。 证据：[`03-progress/07-progress-drag-preview.png`](03-progress/07-progress-drag-preview.png)、[`03-progress/08-progress-jump-loading.png`](03-progress/08-progress-jump-loading.png)、[`03-progress/09-progress-jump-result.png`](03-progress/09-progress-jump-result.png)。
- **当前fork**：ProgressTrack只注册tap，点击立刻on_jump；没有拖动状态或单独目标预览。
- **差异 / 要求**：增加拖动预览与提交两个状态，松手才跳；异步重排/跳转可显示加载，完成后清理；不让每个MOVE触发翻页重排。

### E05 [可做] 旧位置标记与明确的返回原进度入口

- **微信读书**：轨道有灰色旧位置标记。补拍《审判》从26页拖到51%附近后，正文上出现“‹ 返回原进度”描边胶囊；途中多次轨道跳转后点击它，仍回到跳转前26页原段落，并自动收起工具栏/面板。未确认灰点本身点击可返回。 证据：[`03-progress/07-progress-drag-preview.png`](03-progress/07-progress-drag-preview.png)、[`03-progress/10-tap-progress-track.png`](03-progress/10-tap-progress-track.png)、[`15-supplement/13-progress-before-jump.png`](15-supplement/13-progress-before-jump.png)、[`15-supplement/14-progress-after-drag-jump.png`](15-supplement/14-progress-after-drag-jump.png)、[`15-supplement/17-return-original-progress-result.png`](15-supplement/17-return-original-progress-result.png)。
- **当前fork**：已用link.location_stack支持“返回上次位置”文字行，保存/恢复正文锚点的能力明确存在。
- **差异 / 要求**：复用位置栈，可做旧位置视觉标记和明确可点击的返回胶囊，恢复原正文并退出临时跳转状态；不能让连续拖动覆盖返回锚点。灰点的独立点击热区仍未证实，不把普通轨道点选写成返回行为。

### E06 [待定] 统计的进度口径与耗时计算

- **微信读书**：百分比、已读到百分比、剩余分钟在不同画面/重排阶段可能不同；未验证是最远进度还是当前位置，以及时长统计规则。 证据：[`03-progress/01-progress-panel.png`](03-progress/01-progress-panel.png)、[`03-progress/05-progress-panel-after-navigation.png`](03-progress/05-progress-panel-after-navigation.png)、[`06-notes/01-notes-list.png`](06-notes/01-notes-list.png)。
- **当前fork**：进度面板按当前page/page_count计算；本地statistics有自己的计时、平均速度与异常时间规则。
- **差异 / 要求**：可呈现本地真实统计，无法仅凭PNG证明两边算法一致。需明确当前进度/最远进度和估算口径，再定义验收数据。

## F. 自动翻页与划线导读（03-progress）

当前代码落点：[`plugins/autoturn.koplugin/main.lua`](../../../plugins/autoturn.koplugin/main.lua)、[`frontend/apps/reader/modules/readertoolbarpanels.lua`](../../../frontend/apps/reader/modules/readertoolbarpanels.lua)、[`frontend/apps/reader/modules/readerhinting.lua`](../../../frontend/apps/reader/modules/readerhinting.lua)。

### F01 [可做] 从进度面板开启自动翻页

- **微信读书**：面板下方整行“开启自动翻页”，开启后回正文，左下出现自动翻页设置胶囊。 证据：[`03-progress/01-progress-panel.png`](03-progress/01-progress-panel.png)、[`03-progress/02-auto-page-turn.png`](03-progress/02-auto-page-turn.png)、[`03-progress/05-progress-panel-after-navigation.png`](03-progress/05-progress-panel-after-navigation.png)。
- **当前fork**：autoturn插件已有定时翻页、启停、持久化与休眠处理，但只接原菜单；新进度面板未暴露。
- **差异 / 要求**：把现有插件接入此路径，并提供正文中的可见运行标记和设置入口；插件不存在时不要显示无效按钮。

### F02 [可做] 自动翻页设置与停止路径

- **微信读书**：设置区域有速度档位、划线导读开关、收起图标，以及醒目的“关闭自动翻页”。 证据：[`03-progress/03-auto-page-turn-settings.png`](03-progress/03-auto-page-turn-settings.png)、[`03-progress/04-auto-reading-guide-enabled.png`](03-progress/04-auto-reading-guide-enabled.png)。
- **当前fork**：现为DateTimeWidget输入分钟/秒，“Disable”按钮停止，另可设翻页/滚动距离。
- **差异 / 要求**：重做快捷设置与可见停止按钮，复用启动/停止逻辑；保留原版精细时长入口，退出面板不等于退出自动翻页。

### F03 [待定] 1.0至4.0速度档位的时间语义

- **微信读书**：速度刻度为1.0、1.5、2.0、3.0、4.0，未记录实际翻页间隔或与阅读字数的关系。 证据：[`03-progress/03-auto-page-turn-settings.png`](03-progress/03-auto-page-turn-settings.png)。
- **当前fork**：autoturn是每若干秒翻指定距离，不是经过确认的微信速度模型。
- **差异 / 要求**：不能直接把“1.5”解释为1.5秒或1.5倍；需测量后决定与本地秒数的映射。

### F04 [待定] 划线导读的跟随与调度

- **微信读书**：开关打开后正文出现导读横线；静态图没有揭示移动节奏、换行、跨页和暂停规则。 证据：[`03-progress/04-auto-reading-guide-enabled.png`](03-progress/04-auto-reading-guide-enabled.png)。
- **当前fork**：autoturn只定时翻页/滚动；readerhinting是排版性能预备机制，不是逐行阅读导读，未见现成导读状态机。
- **差异 / 要求**：需要新增导读绘制与调度并验证墨水屏刷新；不能把自动翻页能力等同于已有逐行导读，先补录时序。

## G. 全屏目录与全文搜索（04-contents-and-search）

当前代码落点：[`frontend/apps/reader/modules/readertocdrawer.lua`](../../../frontend/apps/reader/modules/readertocdrawer.lua)、[`frontend/apps/reader/modules/readertoc.lua`](../../../frontend/apps/reader/modules/readertoc.lua)、[`frontend/apps/reader/modules/readersearch.lua`](../../../frontend/apps/reader/modules/readersearch.lua)、[`frontend/apps/reader/modules/readertoolbar.lua`](../../../frontend/apps/reader/modules/readertoolbar.lua)。

### G01 [可做] 全屏目录替换侧边抽屉

- **微信读书**：顶部书名和右上“去底部”，搜索框紧随其下，目录占全屏；底部为返回、书签及上一页/下一页。 证据：[`04-contents-and-search/01-contents.png`](04-contents-and-search/01-contents.png)。
- **当前fork**：TocDrawer为min(86%屏宽,560dp)侧抽屉，封面/作者/进度头和目录/书签/笔记三个tabs；CONTEXT也定义为抽屉。
- **差异 / 要求**：重做全屏页并拆掉三tabs作为主导航；同步修订后续DESIGN/CONTEXT和demo的过时抽屉假设，本次只登记需求，不直接改文档。

### G02 [可做] 目录层级折叠与展开

- **微信读书**：PART分组前有展开箭头，折叠后下级行隐藏，保留各级标题和起始页码。 证据：[`04-contents-and-search/01-contents.png`](04-contents-and-search/01-contents.png)、[`04-contents-and-search/02-contents-section-collapsed.png`](04-contents-and-search/02-contents-section-collapsed.png)。
- **当前fork**：tocItems把全部条目展开为带缩进的平铺列表，没有折叠状态；底层ReaderToc保留层级与折叠能力。
- **差异 / 要求**：复用底层数据，补分组折叠/展开和持久的浏览状态，分页随可见条目更新；当前章节的可见性与定位也要保留。

### G03 [可做] 去顶部/底部及列表分页

- **微信读书**：右上可在去底部/去顶部间切换；右下组合式上一页/下一页，边界禁用。 证据：[`04-contents-and-search/01-contents.png`](04-contents-and-search/01-contents.png)、[`04-contents-and-search/03-contents-bottom.png`](04-contents-and-search/03-contents-bottom.png)。
- **当前fork**：抽屉和新UI分页器支持页码翻页，没有目录一键顶/底入口，通常显示n/N和分开的按钮。
- **差异 / 要求**：接入首/末页跳转，统一截图的底部返回和右下胶囊分页外观；保留清晰边界状态。

### G04 [可做] 目录搜索及输入页面

- **微信读书**：目录顶部直接有“搜索全书内容”搜索框，点击后进入搜索输入状态并弹键盘。 证据：[`04-contents-and-search/01-contents.png`](04-contents-and-search/01-contents.png)、[`04-contents-and-search/04-search-input.png`](04-contents-and-search/04-search-input.png)。
- **当前fork**：抽屉没有搜索框；顶栏search通过原ReaderSearch输入对话框，demo有独立全屏搜索页。
- **差异 / 要求**：把搜索接到目录内可见入口，重做输入页及键盘上方布局；高级正则/大小写等既有能力可以收进次级入口，不能直接丢失。

### G05 [可做] 按章节分组的搜索结果

- **微信读书**：搜索词留在顶部输入框，下面章节标题及命中摘要，关键词黑底白字，列表分页。 证据：[`04-contents-and-search/05-search-results.png`](04-contents-and-search/05-search-results.png)。
- **当前fork**：ReaderSearch.findAllText已有全屏Menu结果、上下文与页码，未用本套新样式或按截图分组；demo是新全屏结果列表。
- **差异 / 要求**：保留真实搜索引擎与分页，重绘分组、关键词和摘要布局；以代码为准，不能因demo可点击就写成Lua已经完成。

### G06 [可做] 搜索命中跳转与正文导航条

- **微信读书**：点结果回正文；底部黑条带搜索图标、关键词、返回结果列表和关闭，工具栏出现时显示状态会变化。 证据：[`04-contents-and-search/06-search-hit-in-book.png`](04-contents-and-search/06-search-hit-in-book.png)、[`04-contents-and-search/07-search-return-bar.png`](04-contents-and-search/07-search-return-bar.png)、[`08-listening/13-return-to-original-text.png`](08-listening/13-return-to-original-text.png)。
- **当前fork**：ReaderSearch已有结果跳转、查找控件、保留结果与位置栈，但使用原SearchDialog/按钮布局，新黑色条未做。
- **差异 / 要求**：在现有搜索状态上新增正文黑条，保持关键词和结果页位置；关闭条与回结果列表分别处理，避免关闭工具栏时误结束搜索。

### G07 [可做] 空结果与退出搜索

- **微信读书**：无结果页保留输入框并提示“没有找到相关内容”；关闭正文搜索条回普通阅读。 证据：[`04-contents-and-search/08-search-no-results.png`](04-contents-and-search/08-search-no-results.png)、[`04-contents-and-search/09-search-exited.png`](04-contents-and-search/09-search-exited.png)。
- **当前fork**：原搜索有无结果提示、重开输入及位置返回，呈现为原对话框/通知；demo有自己独立的空状态。
- **差异 / 要求**：统一为全屏搜索内的空状态，提供继续修改词与返回路径；搜索退出后清理临时命中显示，不清除用户划线。

### G08 [可做] 从目录进入书签/笔记

- **微信读书**：目录底部“书签”按钮打开标题为“笔记”的统一列表，而不是另一个目录tabs。 证据：[`04-contents-and-search/01-contents.png`](04-contents-and-search/01-contents.png)、[`04-contents-and-search/03-contents-bottom.png`](04-contents-and-search/03-contents-bottom.png)、[`05-bookmarks/01-bookmarks-before.png`](05-bookmarks/01-bookmarks-before.png)。
- **当前fork**：当前只是抽屉书签tab与笔记tab分开切换，数据也预先分组。
- **差异 / 要求**：目录“书签”入口应路由到同一书的统一笔记页，并按目标筛选展示；不要再新增一份平行数据副本。

## H. 书签（05-bookmarks）

当前代码落点：[`frontend/apps/reader/modules/readertoolbar.lua`](../../../frontend/apps/reader/modules/readertoolbar.lua)、[`frontend/apps/reader/modules/readerdogear.lua`](../../../frontend/apps/reader/modules/readerdogear.lua)、[`frontend/apps/reader/modules/readerbookmark.lua`](../../../frontend/apps/reader/modules/readerbookmark.lua)、[`frontend/apps/reader/modules/readertocdrawer.lua`](../../../frontend/apps/reader/modules/readertocdrawer.lua)。

### H01 [可做] 添加/移除书签与工具栏状态

- **微信读书**：顶部书签动作可切换，添加后有黑色折角与成功提示，已添加时图标对应删除动作。 证据：[`05-bookmarks/02-bookmark-added.png`](05-bookmarks/02-bookmark-added.png)、[`05-bookmarks/03-remove-bookmark-toolbar.png`](05-bookmarks/03-remove-bookmark-toolbar.png)。
- **当前fork**：toggleBookmark已接原书签，bookmarkIcon读当前状态，折角复用原ReaderDogear；未按截图校准提示/折角大小。
- **差异 / 要求**：能力已有，统一图标、折角、提示和状态更新；移除仅影响当前页书签，不应删同页的划线或想法。

### H02 [可做] 统一笔记列表中的书签卡片

- **微信读书**：书签是统一列表中的一种卡片，使用区别于划线的类型图标；总条数含书签。 证据：[`05-bookmarks/01-bookmarks-before.png`](05-bookmarks/01-bookmarks-before.png)、[`05-bookmarks/04-bookmark-in-notes.png`](05-bookmarks/04-bookmark-in-notes.png)、[`05-bookmarks/05-bookmarks-and-highlights-filter.png`](05-bookmarks/05-bookmarks-and-highlights-filter.png)。
- **当前fork**：TocDrawer把无drawer项放bookmarks、带drawer项放notes；书签行显示摘录、章节、页码和日期；CONTEXT明确笔记不含书签。
- **差异 / 要求**：统一展示可以复用annotation，但必须显式调整“列表总数”和术语，避免把数据中的划线/想法分类破坏；领域冲突见 T06。

### H03 [可做] 仅显示书签/显示全部筛选

- **微信读书**：存在书签时右上切换仅书签/全部；本次删除最后书签后入口不再显示。 证据：[`05-bookmarks/04-bookmark-in-notes.png`](05-bookmarks/04-bookmark-in-notes.png)、[`05-bookmarks/05-bookmarks-and-highlights-filter.png`](05-bookmarks/05-bookmarks-and-highlights-filter.png)、[`05-bookmarks/07-temporary-bookmark-removed.png`](05-bookmarks/07-temporary-bookmark-removed.png)。
- **当前fork**：当前用书签/笔记两个固定tabs，没有混合筛选，也不随最后书签消失。
- **差异 / 要求**：新增统一列表过滤与数量反馈，依真实数据决定入口状态；点击筛选后不改变阅读位置。

### H04 [可做] 长按书签删除确认

- **微信读书**：长按测试书签弹出底部确认，整行“删除”“取消”，删除后返回列表。 证据：[`05-bookmarks/06-bookmark-delete-confirmation.png`](05-bookmarks/06-bookmark-delete-confirmation.png)、[`05-bookmarks/07-temporary-bookmark-removed.png`](05-bookmarks/07-temporary-bookmark-removed.png)。
- **当前fork**：新抽屉行只接tap跳转，未接hold；原ReaderBookmark有删除能力。
- **差异 / 要求**：为卡片增加长按确认流程并即时更新数量/筛选；采用底部确认层，取消不能改变数据。

### H05 [可做] 书签跳转与稳定锚点

- **微信读书**：书签卡展示位置摘录；统一列表中划线卡点击跳正文已实测，书签卡点击后的专门画面未单独录下。 证据：[`05-bookmarks/04-bookmark-in-notes.png`](05-bookmarks/04-bookmark-in-notes.png)、[`05-bookmarks/05-bookmarks-and-highlights-filter.png`](05-bookmarks/05-bookmarks-and-highlights-filter.png)、[`06-notes/04-note-jump-to-text.png`](06-notes/04-note-jump-to-text.png)。
- **当前fork**：pageStartText/gotoBookmark已支持流式书与版式书，缺文字可回退章节名，并保存跳转前位置。
- **差异 / 要求**：保留本地书签跳转能力，改卡片和统一页路由时不丢稳定位置和返回栈；补验收书签点选后画面，不将重排前页码作为唯一定位依据。

## I. 笔记列表、计数与空状态（06-notes）

当前代码落点：[`frontend/apps/reader/modules/readertocdrawer.lua`](../../../frontend/apps/reader/modules/readertocdrawer.lua)、[`frontend/apps/reader/modules/readerannotation.lua`](../../../frontend/apps/reader/modules/readerannotation.lua)、[`frontend/apps/reader/modules/readerbookmark.lua`](../../../frontend/apps/reader/modules/readerbookmark.lua)、[`frontend/apps/reader/modules/readerrolling.lua`](../../../frontend/apps/reader/modules/readerrolling.lua)、[`frontend/apps/shelf/meview.lua`](../../../frontend/apps/shelf/meview.lua)。

### I01 [可做] 独立全屏笔记页与书籍概况卡

- **微信读书**：标题“笔记”；圆角描边概况卡，右侧封面，左侧书名、已读到百分比、共几条、阅读分钟。 证据：[`06-notes/01-notes-list.png`](06-notes/01-notes-list.png)、[`06-notes/06-empty-notes-completed-book.png`](06-notes/06-empty-notes-completed-book.png)。
- **当前fork**：抽屉头是封面在左、书名作者在右及章节数；无独立笔记页，无书籍概况描边卡和时长。
- **差异 / 要求**：复用书籍元数据、annotation与statistics，重做全屏页及概况卡，避免只把抽屉拉宽却保留不符的头部。

### I02 [可做] 章节分组的圆角卡片列表

- **微信读书**：大号章节标题，每条为完整黑色圆角描边卡，左侧圆形类型图标，摘录换行，无截图所见日期尾行。 证据：[`06-notes/01-notes-list.png`](06-notes/01-notes-list.png)、[`06-notes/02-notes-next-page.png`](06-notes/02-notes-next-page.png)、[`06-notes/05-notes-last-page.png`](06-notes/05-notes-last-page.png)。
- **当前fork**：buildNoteRow用样式色块、摘录、想法文本、日期和底部分割线；章节标题较小且带横线。
- **差异 / 要求**：重绘分组和卡片，保留原划线样式及想法数据；日期若继续保留要放次级详情，不把现有列表外观当成已复刻。

### I03 [可做] 列表翻页、末页与回列表位置

- **微信读书**：右下双按钮分页，末页下一页变灰；最后一屏可能与前一屏有内容重叠。 证据：[`06-notes/02-notes-next-page.png`](06-notes/02-notes-next-page.png)、[`06-notes/05-notes-last-page.png`](06-notes/05-notes-last-page.png)。
- **当前fork**：TocDrawer有按测量高度分页、分组标题不落页尾、分页缓存和禁用边界，但外观为n/N型，末页算法不一定相同。
- **差异 / 要求**：统一控件样式并保留浏览页；末页重叠不必人为复制，先保证不漏条目、不重复计数和边界正确。

### I04 [可做] 点击笔记回正文并定位

- **微信读书**：点击卡片跳正文，对应内容短暂灰底标识，帮助找到命中位置。 证据：[`06-notes/04-note-jump-to-text.png`](06-notes/04-note-jump-to-text.png)。
- **当前fork**：goTo调用gotoBookmark并保存原位置；流式书还会向GotoXPointer传marker，原ReaderRolling按设置短暂画页边标记，并非截图的整段灰底反馈。
- **差异 / 要求**：保留已有跳转与页边定位能力，校准为对应摘录的临时聚焦；该反馈必须与用户真正的划线样式分开，不能生成新笔记。

### I05 [可做] 笔记长按确认层

- **微信读书**：长按条目有“确认删除该笔记吗？”底部层，删除/取消分行；原有笔记本次只查看后取消。 证据：[`06-notes/03-existing-note-long-press.png`](06-notes/03-existing-note-long-press.png)。
- **当前fork**：新行没有hold删除；底层bookmark/annotation可删，已有划线气泡也能删除。
- **差异 / 要求**：把真实删除接到卡片长按，取消不改数据；区分删除整条划线和仅删除想法，后者见 J05。

### I06 [可做] 统一空状态

- **微信读书**：概况卡保留，下面描边空状态卡提示“你可以在这里记录本书的想法、划线和书签”，分页禁用。 证据：[`06-notes/06-empty-notes-completed-book.png`](06-notes/06-empty-notes-completed-book.png)。
- **当前fork**：当前书签/笔记分开的空状态为居中标题+文字，没有描边卡，说明语义也不含统一三类。
- **差异 / 要求**：按统一笔记页重绘空状态，数据为0也保留书籍概况；不显示假想法/假条数。

### I07 [可做] 新增/删除后的计数与列表一致性

- **微信读书**：临时书签/手写会让总数42变43；删除测试条目后回42，擦掉笔迹本身不一定减少条数。 证据：[`06-notes/07-final-note-count-restored.png`](06-notes/07-final-note-count-restored.png)、[`05-bookmarks/01-bookmarks-before.png`](05-bookmarks/01-bookmarks-before.png)、[`05-bookmarks/07-temporary-bookmark-removed.png`](05-bookmarks/07-temporary-bookmark-removed.png)、[`11-handwriting/09-erased-stroke-note-remains.png`](11-handwriting/09-erased-stroke-note-remains.png)、[`11-handwriting/11-test-handwriting-removed.png`](11-handwriting/11-test-handwriting-removed.png)。
- **当前fork**：annotation有统一变更事件，但抽屉在init时快照拆分数据，me页另有缓存；当前不支持手写类型。
- **差异 / 要求**：所有相关页面在变更后刷新数据、计数和筛选；统一笔记页总数与类型口径一致。手写未来接入时不能以“无可见线条”推断条目已删除。

## J. 写想法、私密状态与自己的想法详情（07）

当前代码落点：[`frontend/apps/reader/modules/readerhighlightbubble.lua`](../../../frontend/apps/reader/modules/readerhighlightbubble.lua)、[`frontend/apps/reader/modules/readerannotation.lua`](../../../frontend/apps/reader/modules/readerannotation.lua)、[`frontend/apps/reader/modules/readerbookmark.lua`](../../../frontend/apps/reader/modules/readerbookmark.lua)、[`frontend/ui/widget/inputtext.lua`](../../../frontend/ui/widget/inputtext.lua)。

### J01 [可做] 贴近键盘的紧凑想法编辑器

- **微信读书**：选词写想法后背景压淡，键盘上方只有紧凑输入带、引用及右侧“发表”，左侧返回，右下私密标记。 证据：[`07-selection-and-lookup/04-write-thought-editor.png`](07-selection-and-lookup/04-write-thought-editor.png)、[`07-selection-and-lookup/06-private-thought-draft.png`](07-selection-and-lookup/06-private-thought-draft.png)、[`14-community/17-community-thought-editor.png`](14-community/17-community-thought-editor.png)。
- **当前fork**：showNoteSheet为带标题的BottomSheet，引用在前、大描边输入框及底部取消/保存；会按键盘高度调整。
- **差异 / 要求**：复用输入、引用和避让键盘能力，重做紧凑布局、返回与提交位置；本地提交应明确是保存，不能把没有云后端的动作写成公开“发表”。

### J02 [可做] 保存、草稿与取消清理

- **微信读书**：测试文字提交后有保存反馈；从社区想法进入空编辑器可取消，本次没有发表该草稿。 证据：[`07-selection-and-lookup/06-private-thought-draft.png`](07-selection-and-lookup/06-private-thought-draft.png)、[`07-selection-and-lookup/07-private-test-thought-saved.png`](07-selection-and-lookup/07-private-test-thought-saved.png)、[`07-selection-and-lookup/12-test-thought-deleted.png`](07-selection-and-lookup/12-test-thought-deleted.png)、[`14-community/17-community-thought-editor.png`](14-community/17-community-thought-editor.png)。
- **当前fork**：本地想法存annotation.note；新建时先保存划线，取消会通过is_new清掉临时条目。
- **差异 / 要求**：保留保存持久化和取消不留垃圾数据；重做界面时测试键盘返回、关闭、二次进入和多页选区，不把取消当成保存空想法。

### J03 [待定] 私密标记的准确含义与交互

- **微信读书**：编辑器有“私密”，本次该节点不可点击；保存后详情明确“仅自己可见”，未看到可见范围选择菜单。 证据：[`07-selection-and-lookup/04-write-thought-editor.png`](07-selection-and-lookup/04-write-thought-editor.png)、[`07-selection-and-lookup/05-private-visibility-indicator.png`](07-selection-and-lookup/05-private-visibility-indicator.png)、[`07-selection-and-lookup/09-private-thought-full-detail.png`](07-selection-and-lookup/09-private-thought-full-detail.png)。
- **当前fork**：本地想法没有微信的公开/仅自己可见状态，数据只存本地并可能由用户另行导出同步。
- **差异 / 要求**：不要凭标记实现一个虚构的私密/公开开关。可考虑明确“本地保存”，但是否展示隐私标记及同步后的表述需产品决定。

### J04 [可做] 正文想法卡片与本地详情页

- **微信读书**：点有想法的词显示引用与内容卡片，再点内容进入全屏详情，引用可返回书内位置。 证据：[`07-selection-and-lookup/08-private-thought-detail.png`](07-selection-and-lookup/08-private-thought-detail.png)、[`07-selection-and-lookup/09-private-thought-full-detail.png`](07-selection-and-lookup/09-private-thought-full-detail.png)。
- **当前fork**：点已有划线走showHighlightBubble，直接显示样式/修改想法/复制/查询/删除，未先展示想法内容卡及独立详情。
- **差异 / 要求**：补本地内容卡和详情阅读路径，复用摘录、正文定位、编辑和删除；云作者身份、赞和评论属于 J06，不用假账号填充。

### J05 [待定] 想法与显式划线的独立生命周期

- **微信读书**：想法卡引用旁仍有“划线”动作；删除私密想法后单词不再带该想法。样本表明两种动作可分开，但未穷举先划线后写想法等组合。 证据：[`07-selection-and-lookup/08-private-thought-detail.png`](07-selection-and-lookup/08-private-thought-detail.png)、[`07-selection-and-lookup/11-test-thought-delete-confirmation.png`](07-selection-and-lookup/11-test-thought-delete-confirmation.png)、[`07-selection-and-lookup/12-test-thought-deleted.png`](07-selection-and-lookup/12-test-thought-deleted.png)、[`07-selection-and-lookup/13-highlight-added.png`](07-selection-and-lookup/13-highlight-added.png)。
- **当前fork**：当前“写想法”一定先saveSelection成一条有drawer的划线；清空note保留划线，删highlight则两者一起删。
- **差异 / 要求**：需补测微信四种创建/删除顺序，再决定是否支持无可见划线的想法、以及删除只删文字还是整条条目。不能只换删除文案而保留错误数据语义。

### J06 [微信读书独有] 云想法作者身份、赞与评论

- **微信读书**：自己的想法详情显示头像昵称、仅自己可见、赞/评论标签及空列表。 证据：[`07-selection-and-lookup/08-private-thought-detail.png`](07-selection-and-lookup/08-private-thought-detail.png)、[`07-selection-and-lookup/09-private-thought-full-detail.png`](07-selection-and-lookup/09-private-thought-full-detail.png)、[`07-selection-and-lookup/10-thought-likes-tab.png`](07-selection-and-lookup/10-thought-likes-tab.png)。
- **当前fork**：本地annotation没有账号、云想法ID、赞和评论关系；当前只有文本编辑与本地保存。
- **差异 / 要求**：仅本地内容展示可复用；微信作者身份、云可见性和互动列表不实现为假数据。自己的想法也不等于KOReader账号下的一条云动态。

## K. 文字选择与划线菜单（07-selection-and-lookup）

当前代码落点：[`frontend/apps/reader/modules/readerhighlightbubble.lua`](../../../frontend/apps/reader/modules/readerhighlightbubble.lua)、[`frontend/apps/reader/modules/readerhighlight.lua`](../../../frontend/apps/reader/modules/readerhighlight.lua)、[`frontend/ui/widget/selectionbubble.lua`](../../../frontend/ui/widget/selectionbubble.lua)、[`frontend/apps/reader/modules/readerview.lua`](../../../frontend/apps/reader/modules/readerview.lua)、[`frontend/document/credocument.lua`](../../../frontend/document/credocument.lua)。

### K01 [可做] 白底描边选词浮层

- **微信读书**：白底、黑色细描边、圆角与指向选词的小三角；每项有图标加短文字，页底时放在选词上方。 证据：[`07-selection-and-lookup/01-english-word-selected.png`](07-selection-and-lookup/01-english-word-selected.png)、[`07-selection-and-lookup/17-chinese-text-selected.png`](07-selection-and-lookup/17-chinese-text-selected.png)、[`07-selection-and-lookup/21-bottom-of-page-selection.png`](07-selection-and-lookup/21-bottom-of-page-selection.png)。
- **当前fork**：SelectionBubble画黑底、白文字，动作大多为纯文字，用分割线隔开；已有根据anchor_rects避让上下空间的逻辑。
- **差异 / 要求**：反转浮层视觉并加图标，保留锚点与边缘避让；同步修改DESIGN和demo关于黑气泡的假设，不只改Lua颜色。

### K02 [可做] 动作顺序与中英文分流

- **微信读书**：英文顺序为划线、翻译、写想法、复制、听当前；中文相同位置使用查询。 证据：[`07-selection-and-lookup/01-english-word-selected.png`](07-selection-and-lookup/01-english-word-selected.png)、[`07-selection-and-lookup/17-chinese-text-selected.png`](07-selection-and-lookup/17-chinese-text-selected.png)。
- **当前fork**：onShowHighlightMenu固定复制、划线、写想法、查询、搜索，没有按选中语言分流，也没有“听当前”。
- **差异 / 要求**：把现有四项本地动作按截图排序，英文查词/翻译按 L02接入；全文搜索的扩展位置另定。听当前不能无后端占位，见 M01。

### K03 [可做] 选区的下划线与水滴手柄

- **微信读书**：临时选区以文字下方线条和黑色水滴形两端手柄显示，不是整块黑底反白选区。 证据：[`07-selection-and-lookup/01-english-word-selected.png`](07-selection-and-lookup/01-english-word-selected.png)、[`07-selection-and-lookup/17-chinese-text-selected.png`](07-selection-and-lookup/17-chinese-text-selected.png)、[`07-selection-and-lookup/21-bottom-of-page-selection.png`](07-selection-and-lookup/21-bottom-of-page-selection.png)。
- **当前fork**：生产代码沿用引擎灰色选区，#6已记录；demo和DESIGN却设为黑底反白，未实现同款可见手柄。
- **差异 / 要求**：复用选区起止点、字框与拖动能力，新增临时选区绘制/手柄命中；流式书和版式书分别验证，不把demo的反白效果当作当前Lua事实。

### K04 [可做] 拖动扩选与跨行选中

- **微信读书**：单词长按松手有两端黑手柄；拖动右手柄可跨行扩选，松手自动生成持久划线，菜单切为删除划线；补拍已复现。 证据：[`07-selection-and-lookup/21-bottom-of-page-selection.png`](07-selection-and-lookup/21-bottom-of-page-selection.png)、[`07-selection-and-lookup/23-drag-to-highlight.png`](07-selection-and-lookup/23-drag-to-highlight.png)、[`07-selection-and-lookup/24-expanded-test-highlight-removed.png`](07-selection-and-lookup/24-expanded-test-highlight-removed.png)、[`15-supplement/33-long-press-release-word-handles.png`](15-supplement/33-long-press-release-word-handles.png)、[`15-supplement/34-handle-drag-released.png`](15-supplement/34-handle-drag-released.png)。
- **当前fork**：继承ReaderHighlight的hold_pan扩选、跨页选择与保存；当前没有同款手柄，拖动沿用上游刷新。
- **差异 / 要求**：可补黑色手柄、跨行反馈与菜单定位；持久化触发按K08接入现有选择动作，保留用户原偏好与可删除反馈。

### K05 [可做] 已有划线的同位删除动作

- **微信读书**：已有划线长按时第一项变“删除划线”，其余动作保持同组；删除后回正文。 证据：[`07-selection-and-lookup/13-highlight-added.png`](07-selection-and-lookup/13-highlight-added.png)、[`07-selection-and-lookup/14-highlight-actions.png`](07-selection-and-lookup/14-highlight-actions.png)、[`07-selection-and-lookup/15-test-highlight-removed.png`](07-selection-and-lookup/15-test-highlight-removed.png)。
- **当前fork**：showHighlightBubble先一整行三种样式，下一行写/改想法、复制、查询、删除；删除在末尾。
- **差异 / 要求**：将主要划线/删除动作置同位，保留其他本地操作；删除只更新受影响内容并同步列表，不引入截图没有的多层确认。

### K06 [可做] 复制与成功提示

- **微信读书**：点击复制后选区收起，正文下方短暂黑底提示“已复制到剪贴板”。 证据：[`07-selection-and-lookup/16-copy-confirmation.png`](07-selection-and-lookup/16-copy-confirmation.png)、[`07-selection-and-lookup/17-chinese-text-selected.png`](07-selection-and-lookup/17-chinese-text-selected.png)。
- **当前fork**：已调用Device.input.setClipboardText并用Notification反馈，文案/形状/位置未按本图专门校准。
- **差异 / 要求**：能力已完成；按截图调整反馈样式与消失时机，避免提示残留遮挡紧接着出现的新菜单。

### K07 [待定] 三种划线样式的扩展入口

- **微信读书**：本版只观察到一种直线划线，没有看到马克笔/直线/波浪线选择行。 证据：[`07-selection-and-lookup/13-highlight-added.png`](07-selection-and-lookup/13-highlight-added.png)、[`07-selection-and-lookup/14-highlight-actions.png`](07-selection-and-lookup/14-highlight-actions.png)、[`07-selection-and-lookup/15-test-highlight-removed.png`](07-selection-and-lookup/15-test-highlight-removed.png)。
- **当前fork**：#6与ADR-0003已经实现并持久化三种样式，正文和笔记里均有样式标记。
- **差异 / 要求**：默认新划线可用实机的直线样式；是否保留其他样式及放到哪里需要决定。不能以“微信同款”为由删除原数据，也不能声称第二行样式来自这批截图。

### K08 [可做] 两种拖动扩选均自动保存划线

- **微信读书**：同一原始无划线段落测试：①按住PARC约1秒不松手直接拖再松手；②先长按松手出现“划线”菜单及手柄，再拖手柄扩至多行并松手。两种都会自动出现实线，菜单第一项已是“删除划线”，各自笔记42→43；没有点击“划线”。单词长按松手本身仍只选词。每次测试后点删除划线，最终42条。 证据：[`07-selection-and-lookup/23-drag-to-highlight.png`](07-selection-and-lookup/23-drag-to-highlight.png)、[`07-selection-and-lookup/24-expanded-test-highlight-removed.png`](07-selection-and-lookup/24-expanded-test-highlight-removed.png)、[`15-supplement/30-direct-hold-drag-released.png`](15-supplement/30-direct-hold-drag-released.png)、[`15-supplement/31-direct-drag-note-count.png`](15-supplement/31-direct-drag-note-count.png)、[`15-supplement/32-direct-drag-test-highlight-deleted.png`](15-supplement/32-direct-drag-test-highlight-deleted.png)、[`15-supplement/33-long-press-release-word-handles.png`](15-supplement/33-long-press-release-word-handles.png)、[`15-supplement/34-handle-drag-released.png`](15-supplement/34-handle-drag-released.png)、[`15-supplement/35-handle-drag-note-count.png`](15-supplement/35-handle-drag-note-count.png)、[`15-supplement/36-handle-drag-highlight-delete-menu.png`](15-supplement/36-handle-drag-highlight-delete-menu.png)、[`15-supplement/37-handle-drag-test-highlight-deleted.png`](15-supplement/37-handle-drag-test-highlight-deleted.png)、[`15-supplement/38-notes-restored-42.png`](15-supplement/38-notes-restored-42.png)。
- **当前fork**：ReaderHighlight.onHoldRelease已有单词/多词分流、扩选模式以及default_highlight_action（ask/highlight/select等），saveHighlight可持久保存；同款可拖手柄尚缺。
- **差异 / 要求**：现有本地高亮能力可做该语义：区分仅选词与拖动扩选，扩选结束保存一条并给删除入口，不能重复生成多条。应接入/兼容现有默认动作偏好，不覆盖用户设置。这里确认本机当前行为，未推断微信读书隐藏偏好或所有跨页手势；两条测试划线均已删除。

## L. 查词、翻译与百科（07-selection-and-lookup）

当前代码落点：[`frontend/apps/reader/modules/readerdictsheet.lua`](../../../frontend/apps/reader/modules/readerdictsheet.lua)、[`frontend/apps/reader/modules/readerdictionary.lua`](../../../frontend/apps/reader/modules/readerdictionary.lua)、[`frontend/ui/translator.lua`](../../../frontend/ui/translator.lua)、[`frontend/apps/reader/modules/readerwikipedia.lua`](../../../frontend/apps/reader/modules/readerwikipedia.lua)、[`plugins/vocabbuilder.koplugin/main.lua`](../../../plugins/vocabbuilder.koplugin/main.lua)。

### L01 [可做] 查询结果的全屏卡片结构

- **微信读书**：查询页以多个圆角描边卡竖排：词语、词义/百科摘要、全书繁转简、去书城搜索；正文背景不再露出。 证据：[`07-selection-and-lookup/02-translation-result.png`](07-selection-and-lookup/02-translation-result.png)、[`07-selection-and-lookup/19-chinese-lookup-settled.png`](07-selection-and-lookup/19-chinese-lookup-settled.png)、[`07-selection-and-lookup/22-english-translation-result.png`](07-selection-and-lookup/22-english-translation-result.png)。
- **当前fork**：DictSheet是底部面板，上有词头音标、词典/维基来源chips，释义分条分页，下有生词本/全书搜索/完整词条等。
- **差异 / 要求**：用已有查询结果重排为全屏卡片，保持返回原选词位置；对应本地动作与额外能力应明确，不能照画无效书城/繁简按钮。

### L02 [可做] 英文“翻译”与中文“查询”的能力接入

- **微信读书**：英文Copy有“复制”释义，PARC未返回词义；中文丹佛返回百科；英文菜单用“翻译”。 证据：[`07-selection-and-lookup/01-english-word-selected.png`](07-selection-and-lookup/01-english-word-selected.png)、[`07-selection-and-lookup/17-chinese-text-selected.png`](07-selection-and-lookup/17-chinese-text-selected.png)、[`07-selection-and-lookup/19-chinese-lookup-settled.png`](07-selection-and-lookup/19-chinese-lookup-settled.png)、[`07-selection-and-lookup/22-english-translation-result.png`](07-selection-and-lookup/22-english-translation-result.png)。
- **当前fork**：新气泡统一Look up，ReaderDictSheet已有中英文候选、词形还原与本地StarDict；原Translator另有联网翻译能力但未接该新入口。
- **差异 / 要求**：词级解释优先复用本地词典，必要时接现有Translator并明确联网；不能把英文单词释义一概归为微信AI独有，也不能宣称当前新气泡已经调用翻译后端。

### L03 [可做] 查询中、无词条及成功结果

- **微信读书**：中文先有“查询中…”，随后出现百科摘要；无词义的PARC仍显示词语及后续入口。 证据：[`07-selection-and-lookup/02-translation-result.png`](07-selection-and-lookup/02-translation-result.png)、[`07-selection-and-lookup/18-chinese-lookup-result.png`](07-selection-and-lookup/18-chinese-lookup-result.png)、[`07-selection-and-lookup/19-chinese-lookup-settled.png`](07-selection-and-lookup/19-chinese-lookup-settled.png)、[`07-selection-and-lookup/22-english-translation-result.png`](07-selection-and-lookup/22-english-translation-result.png)。
- **当前fork**：当前本地未命中有明确提示与安装词典说明，Wikipedia有联网、加载、失败状态；新面板外观不同。
- **差异 / 要求**：统一卡片式加载/成功/空状态与返回操作，保留本地未安装词典的真实提示；不复制“无解释只剩书城”而断掉本地可用的补救路径。

### L04 [可做] 百科摘要进入完整内容

- **微信读书**：点百科释义卡的箭头打开内嵌百科详情页，标题、正文和图片可见，并可返回查询。 证据：[`07-selection-and-lookup/19-chinese-lookup-settled.png`](07-selection-and-lookup/19-chinese-lookup-settled.png)、[`07-selection-and-lookup/20-encyclopedia-webview.png`](07-selection-and-lookup/20-encyclopedia-webview.png)。
- **当前fork**：已有Wikipedia简介与完整词条，onFullEntry接原百科弹窗；缺这版全屏层级和返回布局。
- **差异 / 要求**：复用百科数据与原完整内容能力，做摘要卡→全文→返回的统一层级；通用百科交互不依赖微信账号。

### L05 [待定] 是否必须复用搜狗百科这一数据源

- **微信读书**：拍到的详情是搜狗百科网页；没有采集其API、鉴权、离线或错误路径。 证据：[`07-selection-and-lookup/20-encyclopedia-webview.png`](07-selection-and-lookup/20-encyclopedia-webview.png)。
- **当前fork**：当前用Wikipedia和本地词典，没有搜狗适配或通用内嵌浏览器接入这张网页的同款链路。
- **差异 / 要求**：来源不应误标成微信私有能力，也不能假设可直接接入。需决定用现有Wikipedia替代还是新增网页/服务适配，再核实接口及运行平台。

### L06 [微信读书独有] 按选词去微信书城搜索

- **微信读书**：“去书城搜索”以所选词打开微信书城的封面/简介结果列表。 证据：[`07-selection-and-lookup/02-translation-result.png`](07-selection-and-lookup/02-translation-result.png)、[`07-selection-and-lookup/03-selected-text-bookstore-search.png`](07-selection-and-lookup/03-selected-text-bookstore-search.png)、[`07-selection-and-lookup/19-chinese-lookup-settled.png`](07-selection-and-lookup/19-chinese-lookup-settled.png)、[`07-selection-and-lookup/22-english-translation-result.png`](07-selection-and-lookup/22-english-translation-result.png)。
- **当前fork**：本地仅有书架过滤与配置书源的OpenSearch；没有微信图书目录、账号购买/阅读授权。
- **差异 / 要求**：不实现微信书城数据和购买链路。若改为“在书源搜索”是另一个本地需求，需明确书源支持条件与搜索范围，不能只换字冒充同一服务。

### L07 [待定] 生词本、全书搜索和完整词条的次级位置

- **微信读书**：这版卡片中没有当前fork的词典/维基chips、生词本按钮和全书搜索按钮，但有百科详情入口。 证据：[`07-selection-and-lookup/19-chinese-lookup-settled.png`](07-selection-and-lookup/19-chinese-lookup-settled.png)、[`07-selection-and-lookup/22-english-translation-result.png`](07-selection-and-lookup/22-english-translation-result.png)。
- **当前fork**：#7已实现这些额外功能，且完整词条可保留富HTML、插件按钮，词典数据与生词本都可用。
- **差异 / 要求**：需决定这些已实现能力的新入口位置；可以按截图收敛主层级，但不能删除生词记录或把没有拍到当成微信不存在该能力的证明。

## M. 听书与后台播放器（08-listening）

当前代码落点：[`frontend/apps/reader/modules/readertoolbar.lua`](../../../frontend/apps/reader/modules/readertoolbar.lua)、[`frontend/apps/reader/modules/readerhighlightbubble.lua`](../../../frontend/apps/reader/modules/readerhighlightbubble.lua)、[`frontend/apps/reader/readerui.lua`](../../../frontend/apps/reader/readerui.lua)、[`frontend/device/android/device.lua`](../../../frontend/device/android/device.lua)。

### M01 [待定] 普通听书与“听当前”的共同入口

- **微信读书**：底部听书打开完整播放器；选词“听当前”从选中位置朗读，中心图标区分三点等待、播放三角、正在播放的暂停双线。 证据：[`07-selection-and-lookup/25-listen-from-selection.png`](07-selection-and-lookup/25-listen-from-selection.png)、[`08-listening/01-listening-player-paused.png`](08-listening/01-listening-player-paused.png)、[`08-listening/11-playback-loading.png`](08-listening/11-playback-loading.png)、[`08-listening/16-listen-from-selection-playing.png`](08-listening/16-listen-from-selection-playing.png)、[`08-listening/17-selection-playback-paused.png`](08-listening/17-selection-playback-paused.png)。
- **当前fork**：新工具栏和气泡没有听书入口；本次在frontend、plugins及Android桥接检索未找到已接入的TTS/有声书播放模块，#1曾把听书列范围外。
- **差异 / 要求**：通用听书不是微信专利，但目前不是已有能力的换皮。先决定是否新增本地TTS、音频来源及Android/Kindle范围，再实现可用入口；不能把等待三点误当已播放。

### M02 [微信读书独有] 微信AI音色目录与服务

- **微信读书**：音色列表包含AI男声2025A等年份/男女/语言选项，当前选中有勾，更多音色列表分页。 证据：[`08-listening/04-voice-selection.png`](08-listening/04-voice-selection.png)、[`08-listening/05-more-voices.png`](08-listening/05-more-voices.png)、[`08-listening/06-more-voices-next-page.png`](08-listening/06-more-voices-next-page.png)。
- **当前fork**：没有微信云语音、音色ID目录及授权；也没有已接好的本地语音服务。
- **差异 / 要求**：不复制微信音色清单、名称或声线。若新增本地TTS，只展示真实可用音色；列表视觉可以参考，云音色能力不可冒充。

### M03 [待定] 定时关闭面板

- **微信读书**：圆角卡提供关闭、30/60/90分钟及本集结束后关闭；本次验证30分钟倒计时。 证据：[`08-listening/02-sleep-timer.png`](08-listening/02-sleep-timer.png)、[`08-listening/03-sleep-timer-30-minutes.png`](08-listening/03-sleep-timer-30-minutes.png)。
- **当前fork**：无播放器/队列可控制，autosuspend是设备休眠能力，不能代替音频停止。
- **差异 / 要求**：待M01确定后可做通用定时器；需决定后台运行、暂停是否继续计时和到集末的策略，后两项未从截图确认。

### M04 [待定] 语速与仅当前专辑范围

- **微信读书**：语速横向刻度，有1.0和1.5等，右上“仅应用到当前专辑”开关。 证据：[`08-listening/07-playback-speed.png`](08-listening/07-playback-speed.png)、[`08-listening/08-speed-and-album-scope.png`](08-listening/08-speed-and-album-scope.png)。
- **当前fork**：无音频语速或专辑级设置模型；正文排版/自动翻页速度与语速无关。
- **差异 / 要求**：后端支持语速后再接此UI，并定义全局与单书设置的优先级；不能把自动翻页间隔写成朗读倍速。

### M05 [待定] 集列表与章节拆分

- **微信读书**：显示66集及各集时长，长章节有“_1”分集；前/后集按钮切换并播放。 证据：[`08-listening/09-episode-list.png`](08-listening/09-episode-list.png)、[`08-listening/10-episode-list-bottom.png`](08-listening/10-episode-list-bottom.png)、[`08-listening/20-next-episode.png`](08-listening/20-next-episode.png)、[`08-listening/21-previous-episode.png`](08-listening/21-previous-episode.png)。
- **当前fork**：文本目录可用，但没有微信的音频切集/时长/队列数据，文本章节不等于音频分集。
- **差异 / 要求**：本地TTS可按章节组织，但分段规则、时长来源和切集状态需后端方案。不得直接使用文本页码伪造音频时长或66集。

### M06 [待定] 播放、暂停及15秒前后跳转

- **微信读书**：播放显示当前朗读文字；暂停为三角；本次暂停后点后退15秒会恢复播放，前进15秒也处于播放态。 证据：[`08-listening/16-listen-from-selection-playing.png`](08-listening/16-listen-from-selection-playing.png)、[`08-listening/17-selection-playback-paused.png`](08-listening/17-selection-playback-paused.png)、[`08-listening/18-rewind-15-seconds.png`](08-listening/18-rewind-15-seconds.png)、[`08-listening/19-forward-15-seconds.png`](08-listening/19-forward-15-seconds.png)。
- **当前fork**：没有音频时间轴和跳转回调。
- **差异 / 要求**：在选定后端上验证可seek性及暂停/跳转交互；“跳转即恢复播放”是观测行为，不应未经决定直接作为本地默认策略。

### M07 [待定] 听书进度拖动预览与提交

- **微信读书**：按住拖动有白底目标时间气泡及上方目标时间，松手跳到55分钟附近并恢复播放。 证据：[`08-listening/22-seek-drag-preview.png`](08-listening/22-seek-drag-preview.png)、[`08-listening/23-seek-result.png`](08-listening/23-seek-result.png)。
- **当前fork**：只有文字阅读进度轨道，没有音频缓冲、时间轴或seek。
- **差异 / 要求**：必须先有真实可定位音频/朗读游标，再实现预览与提交；不能复用文字页码轨道却显示假的分秒。

### M08 [待定] 返回原文与音文位置对应

- **微信读书**：“原文”返回正文，本次仍可后台继续播放；播放器有当前句子文本。 证据：[`08-listening/13-return-to-original-text.png`](08-listening/13-return-to-original-text.png)、[`08-listening/16-listen-from-selection-playing.png`](08-listening/16-listen-from-selection-playing.png)。
- **当前fork**：已有阅读位置栈，但没有音频句子到正文位置的映射。
- **差异 / 要求**：明确返回的是当前朗读句还是进入播放器前位置，并实测；需要文本与音频游标映射，不能只做关闭播放器面板。

### M09 [待定] 书架迷你播放器及关闭生命周期

- **微信读书**：回书架底部出现封面、章节、时间、播放/暂停和X；点正文展开；点X迷你条消失并停止。 证据：[`08-listening/14-background-mini-player.png`](08-listening/14-background-mini-player.png)、[`08-listening/15-mini-player-paused.png`](08-listening/15-mini-player-paused.png)、[`08-listening/24-expand-mini-player.png`](08-listening/24-expand-mini-player.png)、[`08-listening/25-mini-player-closed.png`](08-listening/25-mini-player-closed.png)。
- **当前fork**：ShelfFileManager和ReaderUI生命周期现只管理阅读/文件UI，没有独立音频会话。
- **差异 / 要求**：如做听书，音频会话须独立于阅读器窗口，支持退出阅读仍播放、展开保留暂停状态、X真正停止；需同时验证休眠和其他书切换，不能只画迷你条。

## N. 图片与脚注（09-images）

当前代码落点：[`frontend/apps/reader/modules/readerhighlight.lua`](../../../frontend/apps/reader/modules/readerhighlight.lua)、[`frontend/ui/widget/imageviewer.lua`](../../../frontend/ui/widget/imageviewer.lua)、[`frontend/apps/reader/modules/readerlink.lua`](../../../frontend/apps/reader/modules/readerlink.lua)、[`frontend/ui/widget/footnotewidget.lua`](../../../frontend/ui/widget/footnotewidget.lua)、[`frontend/apps/reader/modules/readerhighlightbubble.lua`](../../../frontend/apps/reader/modules/readerhighlightbubble.lua)。

### N01 [可做] 点击图片进入黑底全屏预览

- **微信读书**：点正文插图后进入黑底预览，图片居中，没有常驻标题栏或按钮。 证据：[`09-images/02-image-preview.png`](09-images/02-image-preview.png)。
- **当前fork**：ReaderHighlight.onHold会先识别图片并直接打开ImageViewer；现有viewer默认白底frame、点图切换底部按钮，新界面未改为截图的点击入口。
- **差异 / 要求**：复用现有图片提取/缩放能力，补单击识图路径及黑底全屏样式；与链接和翻页热区的优先级需明确，不要让点图变成翻页。

### N02 [可做] 图片放大与返回

- **微信读书**：预览中双击后图片局部放大并超出边缘，结束预览回原正文位置。 证据：[`09-images/02-image-preview.png`](09-images/02-image-preview.png)、[`09-images/03-image-preview-zoom.png`](09-images/03-image-preview-zoom.png)。
- **当前fork**：ImageViewer已有缩放、捏合、拖动、边缘滑动缩放及关闭，未注册截图所需的double_tap缩放事件。
- **差异 / 要求**：在现有viewer增加双击适合屏幕/放大切换，复用平移和缩放；保持原图比例和阅读位置，不因关图重开书。

### N03 [待定] 图片对象的划线与写想法

- **微信读书**：长按图片弹出仅“划线”“写想法”的菜单，图片有两端选中手柄。 证据：[`09-images/01-image-long-press.png`](09-images/01-image-long-press.png)。
- **当前fork**：当前长按图片优先开ImageViewer；文字annotation有范围与文本，未见可直接用于流式书插图的独立图像笔记模型。
- **差异 / 要求**：对象类型菜单可以重绘，但要先决定插图稳定ID、重排后的锚定和无文本引用的保存方式；不能只把空字符串当作已支持图片笔记。

### N04 [待定] 脚注弹层的具体视觉与路径

- **微信读书**：补拍查看《蘋果之道》目录与“注释”章节：后者是普通正文，列缩写、来源和外部下载链接，不是脚注弹层；原选词测试章节及《审判》26–29页也未找到可点击脚注标记。没有找到可拍的脚注弹层，未穷举385本。 证据：[`04-contents-and-search/03-contents-bottom.png`](04-contents-and-search/03-contents-bottom.png)、[`09-images/02-image-preview.png`](09-images/02-image-preview.png)、[`15-supplement/39-footnote-search-toc.png`](15-supplement/39-footnote-search-toc.png)、[`15-supplement/40-apple-endnotes-chapter.png`](15-supplement/40-apple-endnotes-chapter.png)、[`15-supplement/42-trial-final-position-restored.png`](15-supplement/42-trial-final-position-restored.png)。
- **当前fork**：ReaderLink和FootnoteWidget已支持脚注识别、弹层和跳正文，并有设置入口；目标视觉仍缺实机证据。
- **差异 / 要求**：保留待定，原因是未找到带可点击脚注的已查样本，不表示微信读书没有脚注。既有本地脚注功能保留；以后找到书再确认层宽、按钮、翻页/返回，不套用图片黑底。

## O. 繁简转换、书架与下载等书籍操作（10）

当前代码落点：[`frontend/apps/reader/modules/readertoolbar.lua`](../../../frontend/apps/reader/modules/readertoolbar.lua)、[`frontend/apps/shelf/shelfview.lua`](../../../frontend/apps/shelf/shelfview.lua)、[`frontend/apps/shelf/shelf.lua`](../../../frontend/apps/shelf/shelf.lua)、[`frontend/apps/opds/booksource.lua`](../../../frontend/apps/opds/booksource.lua)、[`frontend/apps/opds/booksourceview.lua`](../../../frontend/apps/opds/booksourceview.lua)、[`plugins/opds.koplugin/main.lua`](../../../plugins/opds.koplugin/main.lua)。

### O01 [待定] 全书繁简转换与恢复

- **微信读书**：顶部简/繁可切换正文；查询卡也有“全书繁转简”入口；采集测试过顶栏切换并恢复繁体，未点击查询卡内转换。 证据：[`10-conversion-and-book-actions/01-convert-to-simplified.png`](10-conversion-and-book-actions/01-convert-to-simplified.png)、[`10-conversion-and-book-actions/02-traditional-restored.png`](10-conversion-and-book-actions/02-traditional-restored.png)、[`07-selection-and-lookup/02-translation-result.png`](07-selection-and-lookup/02-translation-result.png)、[`07-selection-and-lookup/19-chinese-lookup-settled.png`](07-selection-and-lookup/19-chinese-lookup-settled.png)、[`07-selection-and-lookup/22-english-translation-result.png`](07-selection-and-lookup/22-english-translation-result.png)。
- **当前fork**：未在当前frontend/plugins找到已接入的繁简转换后端；字体的简繁字形支持不等于转换原文字串。
- **差异 / 要求**：不依赖微信账号，故不归微信独有；但不是现成换皮。需确定OpenCC类转换方案、文本/搜索/选区锚点兼容性及是否只改渲染，禁止改写原文件作为无提示默认。

### O02 [可做] 阅读器中的加入/移出书架入口

- **微信读书**：点已加入图标弹底部“将…移出书架吗？”确认，移除/取消分行；本次取消。 证据：[`10-conversion-and-book-actions/03-bookshelf-action.png`](10-conversion-and-book-actions/03-bookshelf-action.png)。
- **当前fork**：ShelfView.removeBook已有隐藏书且不删文件；阅读器顶栏只有返回，没有该书架状态动作，书架自身移除直接生效并通知。
- **差异 / 要求**：在阅读器接入本地书架收录/隐藏状态和同款确认层；明确主目录外、已隐藏和仍在阅读的书如何处理，不能把“移出”接到删除文件。

### O03 [可做] 下载状态与开始下载反馈的通用呈现

- **微信读书**：点击云下载后有“已开始下载本书所有可阅读内容”提示及右上状态；书架以勾标出本地内容。 证据：[`10-conversion-and-book-actions/04-offline-download-action.png`](10-conversion-and-book-actions/04-offline-download-action.png)、[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`08-listening/25-mini-player-closed.png`](08-listening/25-mini-player-closed.png)。
- **当前fork**：#24书源已支持下载进度、取消、下载记录与本地勾标；#27合并后下载完成留在书源并标记，点击已下载书再打开，不是#24初稿的自动打开。
- **差异 / 要求**：统一下载中/已本地状态及提示视觉，复用实际书源下载记录；当前行为以合并代码为准，不能把已废弃的自动打开写成现状。

### O04 [待定] 阅读中“下载全部可阅读内容”的适用范围

- **微信读书**：微信阅读器可对当前书触发完整可读内容下载，暗含云分章/阅读授权。 证据：[`10-conversion-and-book-actions/04-offline-download-action.png`](10-conversion-and-book-actions/04-offline-download-action.png)。
- **当前fork**：本地EPUB/PDF打开前已是完整文件；新书源下载整文件，#24明确未在阅读器接书源，PSE流式阅读仍在原版。
- **差异 / 要求**：本地完整文件无需假云下载键；若为书源书保留重新下载，要有源关联及覆盖策略。分章下载/流式阅读需单独评估，不能与现有OPDS下载混称同一能力。

### O05 [微信读书独有] 仅下载账号被授权的微信书籍内容

- **微信读书**：提示限定“所有可阅读内容”，对应微信书籍和账号阅读权益；本次未验证购买或锁章。 证据：[`10-conversion-and-book-actions/04-offline-download-action.png`](10-conversion-and-book-actions/04-offline-download-action.png)。
- **当前fork**：本地书及自配OPDS服务器没有微信购买、会员与锁章授权。
- **差异 / 要求**：不实现微信鉴权、DRM或会员内容获取；界面只能展示本地/书源真实可用资源，不能生成付费/已购状态。

## P. 手写模式与手写笔记（11-handwriting）

当前代码落点：[`frontend/device/input.lua`](../../../frontend/device/input.lua)、[`frontend/apps/reader/modules/readerhandmade.lua`](../../../frontend/apps/reader/modules/readerhandmade.lua)、[`frontend/apps/reader/modules/readerannotation.lua`](../../../frontend/apps/reader/modules/readerannotation.lua)、[`frontend/apps/reader/modules/readertoolbar.lua`](../../../frontend/apps/reader/modules/readertoolbar.lua)。

### P01 [待定] 自由手写模式的入口、工具与退出

- **微信读书**：顶部手写进入独立模式，右上退出，底部独立上一页、画笔/橡皮擦、下一页；可在正文空白画水平线。 证据：[`11-handwriting/01-handwriting-mode.png`](11-handwriting/01-handwriting-mode.png)、[`11-handwriting/02-test-stroke-and-eraser-selected.png`](11-handwriting/02-test-stroke-and-eraser-selected.png)。
- **当前fork**：新顶栏无手写；Input有低层stylus回调，但未见阅读页自由笔迹绘制、保存模块。readerhandmade是手工目录/隐藏流程，不是手写笔记。
- **差异 / 要求**：需新增绘制后端与触摸/笔输入路由，再谈同款模式UI；不能因模块名handmade或stylus事件存在就标成已支持自由手写。

### P02 [待定] 橡皮擦的命中语义与笔迹删除

- **微信读书**：橡皮擦选中后，本次点击线条可擦除；连续擦动未成功。未观察到笔粗/颜色等展开菜单。 证据：[`11-handwriting/02-test-stroke-and-eraser-selected.png`](11-handwriting/02-test-stroke-and-eraser-selected.png)、[`11-handwriting/05-test-stroke-erased.png`](11-handwriting/05-test-stroke-erased.png)。
- **当前fork**：没有可编辑笔画对象、橡皮擦命中或撤销机制。
- **差异 / 要求**：需决定整笔擦除还是局部擦除并实测；此次只能记录点擦有效，不能规定所有设备都必须禁用擦动，也不能凭无效长按新增笔设置菜单。

### P03 [待定] 手写时翻页与重排锚定

- **微信读书**：手写模式有专用翻页控件；退出后回正常正文，清理后没有测试线条。 证据：[`11-handwriting/06-page-turn-in-handwriting-mode.png`](11-handwriting/06-page-turn-in-handwriting-mode.png)、[`11-handwriting/07-clean-reading-after-test-removal.png`](11-handwriting/07-clean-reading-after-test-removal.png)。
- **当前fork**：文本/版式书阅读和文字annotation已有，但没有页内笔画与重排位置的绑定。
- **差异 / 要求**：先决定手写范围是版式书还是也支持流式书；字号、边距、旋转改变后如何锚定是实质工作，不能只按截图像素存一张固定覆盖图。

### P04 [待定] 手写笔记缩略图与独立生命周期

- **微信读书**：擦掉线条后笔记列表仍保留页面缩略图卡，长按删除才移除，总条数回落。 证据：[`11-handwriting/09-erased-stroke-note-remains.png`](11-handwriting/09-erased-stroke-note-remains.png)、[`11-handwriting/10-test-handwriting-delete-confirmation.png`](11-handwriting/10-test-handwriting-delete-confirmation.png)、[`11-handwriting/11-test-handwriting-removed.png`](11-handwriting/11-test-handwriting-removed.png)、[`06-notes/07-final-note-count-restored.png`](06-notes/07-final-note-count-restored.png)。
- **当前fork**：annotation和笔记页没有手写类型或页面预览笔记，只有书签/文字划线/附属想法。
- **差异 / 要求**：如支持手写，新增类型、缩略图与删除路径，区分擦笔迹和删笔记；是否保留空手写条目需要明确，不必复制样本的残留现象。

### P05 [待定] 真实手写笔、延迟和刷新支持

- **微信读书**：这次用ADB触摸输入模拟笔画，没有实体笔、压力、掌拒或连续书写的证据。 证据：[`11-handwriting/01-handwriting-mode.png`](11-handwriting/01-handwriting-mode.png)、[`11-handwriting/02-test-stroke-and-eraser-selected.png`](11-handwriting/02-test-stroke-and-eraser-selected.png)。
- **当前fork**：底层stylus支持有平台差异，不能证明Boox Android桥接和Kindle具备同等笔事件、压力及低延迟墨迹。
- **差异 / 要求**：按设备核实能力与刷新成本后再承诺；界面原型不能代替真实硬件校准。

## Q. 书末页与读完状态（12-book-ending）

当前代码落点：[`frontend/apps/reader/modules/readerstatus.lua`](../../../frontend/apps/reader/modules/readerstatus.lua)、[`frontend/ui/widget/bookstatuswidget.lua`](../../../frontend/ui/widget/bookstatuswidget.lua)、[`frontend/apps/shelf/me.lua`](../../../frontend/apps/shelf/me.lua)、[`frontend/apps/shelf/shelfview.lua`](../../../frontend/apps/shelf/shelfview.lua)。

### Q01 [可做] 书末的独立读完页面

- **微信读书**：已读完《正念的奇迹》书末显示“已读完”；未读完《审判》到最后正文页296/296再翻一次，出现“全书完”、完字徽章、标记读完、统计/推荐卡、退出阅读。 证据：[`12-book-ending/01-completed-book-open.png`](12-book-ending/01-completed-book-open.png)、[`12-book-ending/02-completed-book-contents-bottom.png`](12-book-ending/02-completed-book-contents-bottom.png)、[`12-book-ending/04-book-end.png`](12-book-ending/04-book-end.png)、[`12-book-ending/05-book-end-toolbars.png`](12-book-ending/05-book-end-toolbars.png)、[`15-supplement/20-last-page-before-finish.png`](15-supplement/20-last-page-before-finish.png)、[`15-supplement/21-finish-page-mark-button.png`](15-supplement/21-finish-page-mark-button.png)。
- **当前fork**：ReaderStatus.onEndOfBook默认是原ButtonDialog，提供标记、书籍状态、回开头、下个文件、删除、文件浏览器等；可配置其他结束动作。
- **差异 / 要求**：可做全屏书末页，并按当前完成状态呈现已读完/标记读完；保留继续阅读、退出及已有结束动作，不把删除文件做成误触主动作。到末页与完成标记分开，见Q02。

### Q02 [可做] 到最后正文页与手动标记读完分离

- **微信读书**：原未读完的《审判》从26页拖到100%后先到译后记最后正文页296/296；再点下一页才出现“全书完”及下划线“标记读完”按钮。未点击，直接返回原26页；随后书架《审判》仍没有读完角标，对照《正念的奇迹》原有角标。因此这次到书末没有自动完成。 证据：[`12-book-ending/01-completed-book-open.png`](12-book-ending/01-completed-book-open.png)、[`12-book-ending/04-book-end.png`](12-book-ending/04-book-end.png)、[`15-supplement/18-drag-unfinished-book-to-end.png`](15-supplement/18-drag-unfinished-book-to-end.png)、[`15-supplement/19-unfinished-book-end-result.png`](15-supplement/19-unfinished-book-end-result.png)、[`15-supplement/20-last-page-before-finish.png`](15-supplement/20-last-page-before-finish.png)、[`15-supplement/21-finish-page-mark-button.png`](15-supplement/21-finish-page-mark-button.png)、[`15-supplement/22-unfinished-book-position-restored.png`](15-supplement/22-unfinished-book-position-restored.png)、[`15-supplement/24-shelf-before-gesture-tests.png`](15-supplement/24-shelf-before-gesture-tests.png)。
- **当前fork**：支持end_document_auto_mark与end_document_action，也可在书架手动切完成/在读。
- **差异 / 要求**：现有完成状态与结束动作可支撑同款手动标记路径，按书状态显示按钮；不能只因到100%就写完成。保留用户已选的自动标记策略。这轮未提交按钮，不据此声称完成后动画/同步/第N本计数已验证（见Q03）。

### Q03 [待定] “读完的第N本”的统计口径

- **微信读书**：完成徽章显示47本，未核实是否账号终身总数、重读是否重复，以及删除书后如何计算。 证据：[`12-book-ending/04-book-end.png`](12-book-ending/04-book-end.png)。
- **当前fork**：Me.counts当前计算历史记录中的今年读完数量，使用本地sidecar状态及修改时间，不是账号累计47本的口径。
- **差异 / 要求**：本地累计徽章可做，但需定义范围、时间与重读规则；不能直接拿“今年完成”替代“累计第N本”而不改标签。

### Q04 [可做] 书末退出与工具栏兼容

- **微信读书**：书末仍可上滑打开上下工具栏；“退出阅读”在页面下方，工具栏可能覆盖其部分区域。 证据：[`12-book-ending/04-book-end.png`](12-book-ending/04-book-end.png)、[`12-book-ending/05-book-end-toolbars.png`](12-book-ending/05-book-end-toolbars.png)。
- **当前fork**：原结束弹窗与工具栏各自独立，已有backToShelf/关闭阅读能力，无新书末布局。
- **差异 / 要求**：书末页须与工具栏、目录、笔记兼容，退出返回书架且更新状态；避免底部工具栏遮住唯一退出按钮。

### Q05 [微信读书独有] 推荐值、全站评价数与推荐内容

- **微信读书**：读完页有92.2%推荐值、推荐/一般/不行人数及推荐内容区域。 证据：[`12-book-ending/04-book-end.png`](12-book-ending/04-book-end.png)、[`14-community/05-book-reviews-all.png`](14-community/05-book-reviews-all.png)。
- **当前fork**：KOReader的BookStatusWidget有个人星级与本地书评，但没有全站评价聚合或云推荐。
- **差异 / 要求**：全站推荐数据不实现；不能用个人星级或随机数冒充群体推荐值。个人书评可保留独立入口，属于T09的本地扩展。

## R. 阅读偏好、界面字号与个人页入口（13）

当前代码落点：[`frontend/apps/settings/einksettings.lua`](../../../frontend/apps/settings/einksettings.lua)、[`frontend/ui/elements/eink_settings_order.lua`](../../../frontend/ui/elements/eink_settings_order.lua)、[`frontend/ui/elements/page_turns.lua`](../../../frontend/ui/elements/page_turns.lua)、[`frontend/ui/elements/screen_dpi_menu_table.lua`](../../../frontend/ui/elements/screen_dpi_menu_table.lua)、[`frontend/apps/reader/modules/readerfooter.lua`](../../../frontend/apps/reader/modules/readerfooter.lua)、[`frontend/apps/shelf/meview.lua`](../../../frontend/apps/shelf/meview.lua)。

### R01 [可做] 从个人页进入设置及常用阅读偏好列表

- **微信读书**：个人页列表中有设置；设置为分页行列表，常用阅读开关在同一层，后面有缓存、隐私、反馈等。 证据：[`13-reading-preferences/01-profile-entry.png`](13-reading-preferences/01-profile-entry.png)、[`13-reading-preferences/02-settings.png`](13-reading-preferences/02-settings.png)、[`13-reading-preferences/04-settings-last-page.png`](13-reading-preferences/04-settings-last-page.png)。
- **当前fork**：我的页设置入口已有；设置按阅读/屏幕/网络与同步/设备/高级五组，常用偏好需进入组和原菜单。
- **差异 / 要求**：可在现有分组之上提供截图式常用阅读偏好层，保留其余能力和原版入口；不要把整个五组结构直接删掉。

### R02 [可做] 左侧下一页开启后左右均向后翻

- **微信读书**：初始关；打开后在《蘋果之道》左侧点击87→88，随后右侧88→89，左右都是下一页。关回原值后，左侧两次89→88→87。开启黑底白点在右，关闭描边黑点在左。 证据：[`13-reading-preferences/02-settings.png`](13-reading-preferences/02-settings.png)、[`15-supplement/23-left-side-next-enabled.png`](15-supplement/23-left-side-next-enabled.png)、[`15-supplement/25-left-next-test-baseline.png`](15-supplement/25-left-next-test-baseline.png)、[`15-supplement/26-enabled-left-tap-next.png`](15-supplement/26-enabled-left-tap-next.png)、[`15-supplement/27-enabled-right-tap-next.png`](15-supplement/27-enabled-right-tap-next.png)、[`15-supplement/28-left-side-next-restored-off.png`](15-supplement/28-left-side-next-restored-off.png)、[`15-supplement/29-default-left-taps-position-restored.png`](15-supplement/29-default-left-taps-position-restored.png)。
- **当前fork**：已有翻页方向、点击区、自定义热区；ReaderToolbar.getTapLayout的inverse_reading_order只交换默认左右方向，不等于本次观测到的左右均下一页。
- **差异 / 要求**：用真实点击区能力实现该独立开关，开启只将原左侧上一页区域改下一页，右侧保留下一页；关闭恢复原布局/用户偏好，不直接复用左右交换开关。已测试并恢复；滑动、实体键未在本轮测试，不扩写影响范围。

### R03 [可做] 全局正文首行缩进的快捷入口

- **微信读书**：全局有正文首行缩进开关，书内又有首行顶格/缩进子面板。 证据：[`13-reading-preferences/02-settings.png`](13-reading-preferences/02-settings.png)、[`02-typography/06-paragraph-indent.png`](02-typography/06-paragraph-indent.png)、[`02-typography/15-paragraph-settings-restored.png`](02-typography/15-paragraph-settings-restored.png)。
- **当前fork**：排版面板通过样式微调控制段首缩进，已有全局/单书设置路径；新偏好层无直接开关。
- **差异 / 要求**：提供快捷开关并明确全局默认与单书覆盖；不能切全局后无提示覆盖所有已保存书籍样式。

### R04 [可做] 阅读时显示时间

- **微信读书**：开关开启，普通正文左下显示时间，关闭逻辑本次未专门补拍。 证据：[`13-reading-preferences/02-settings.png`](13-reading-preferences/02-settings.png)、[`00-entry/03-final-reading-position.png`](00-entry/03-final-reading-position.png)。
- **当前fork**：ReaderFooter已有时间项，默认被新工具栏启用，藏在页脚信息设置中。
- **差异 / 要求**：把已有项接到直接开关并同步页脚实时状态；用户自定义页脚布局和开关值应一致，保持系统时间来源。

### R05 [待定] 独立的界面字号控制

- **微信读书**：页面明确说此项调界面字体，正文在书内另调；下方胶囊加减轨道，初始“默认”。 证据：[`13-reading-preferences/03-interface-font-size.png`](13-reading-preferences/03-interface-font-size.png)。
- **当前fork**：新UI字体按角色固定dp，现有Screen DPI改变整体尺寸，文件条目另有字号设置，未见覆盖所有新界面且不影响正文的统一字号比例。
- **差异 / 要求**：需要定义独立UI字号策略并覆盖自绘组件，不能直接改DPI冒充。还需验证变大后的标题、卡片、分页、键盘避让和正文保持不变。

### R06 [可做] 缓存用量与清理入口的本地范围

- **微信读书**：设置中有“清理缓存”和当前体积；本次未触发清理。 证据：[`13-reading-preferences/02-settings.png`](13-reading-preferences/02-settings.png)、[`13-reading-preferences/04-settings-last-page.png`](13-reading-preferences/04-settings-last-page.png)。
- **当前fork**：现有封面/元数据缓存、书源缩略图缓存与原版管理路径，但新五组未集中显示同款缓存行。
- **差异 / 要求**：可整合本地可重建缓存用量与入口，明确不含书籍、annotations、下载记录和设置；截图没有清理确认流程，执行层交互需另行校准。

### R07 [可做] 个人页阅读总时长的本地呈现

- **微信读书**：昵称下为累计阅读219小时25分钟等个人统计，小字呈现，而不是主屏周柱状图。 证据：[`13-reading-preferences/01-profile-entry.png`](13-reading-preferences/01-profile-entry.png)。
- **当前fork**：MeView主屏是本周柱状图、连续天数/今年完成和全局笔记/生词本/传书；statistics有累计时长能力。
- **差异 / 要求**：可用真实本地总时长做相同信息层级；应标识本地统计范围，不能把截图账号的219小时或云累计拷入。周图的保留位置见T08。

## S. 社区、书评与微信账号入口（14-community、13）

当前代码落点：[`frontend/apps/reader/modules/readertoolbar.lua`](../../../frontend/apps/reader/modules/readertoolbar.lua)、[`frontend/apps/reader/modules/readerhighlightbubble.lua`](../../../frontend/apps/reader/modules/readerhighlightbubble.lua)、[`frontend/apps/shelf/meview.lua`](../../../frontend/apps/shelf/meview.lua)、[`frontend/ui/widget/bookstatuswidget.lua`](../../../frontend/ui/widget/bookstatuswidget.lua)。

### S01 [微信读书独有] 社区概况气泡

- **微信读书**：顶部社区图标弹气泡，书评1585、热门划线374及显示/隐藏书友想法入口；正文和书末均可出现。 证据：[`14-community/11-community-popover.png`](14-community/11-community-popover.png)、[`14-community/14-community-popover-in-book.png`](14-community/14-community-popover-in-book.png)。
- **当前fork**：无微信书籍社区数据，工具栏固定本地动作，个人书评数据不能供给这些全站计数。
- **差异 / 要求**：不显示虚假社区按钮和人数；如果无服务则按C03处理布局。单纯能画气泡不等于有对应社区能力。

### S02 [微信读书独有] 全站书评与三类筛选

- **微信读书**：全屏书评页含推荐值统计卡与全部/推荐/一般/不行四个黑白筛选按钮，下方作者书评卡。 证据：[`14-community/05-book-reviews-all.png`](14-community/05-book-reviews-all.png)、[`14-community/06-reviews-recommended.png`](14-community/06-reviews-recommended.png)、[`14-community/07-reviews-average.png`](14-community/07-reviews-average.png)、[`14-community/08-reviews-negative.png`](14-community/08-reviews-negative.png)。
- **当前fork**：只有本地个人星级与书评；没有全站书评内容、评分人数或分类数据。
- **差异 / 要求**：不实现微信书评获取与筛选服务；若将来导入自有数据源，须另定义来源与授权，不能把本地星级当作全站分类。

### S03 [微信读书独有] 书评详情、作者与赞/评论

- **微信读书**：点书评进入全屏详情，显示作者身份和评价类型，列表及详情有赞/评论入口；本次未互动。 证据：[`14-community/09-review-detail.png`](14-community/09-review-detail.png)、[`14-community/05-book-reviews-all.png`](14-community/05-book-reviews-all.png)。
- **当前fork**：本地书评是summary.note，没有云作者、互动及回复数据。
- **差异 / 要求**：不生成社交身份或假互动；本地个人书评只保存自己的内容，可借鉴长文版式，不称社区书评。

### S04 [微信读书独有] 热门划线数据与章节列表

- **微信读书**：热门片段按章节展示，带划线人数，来自其他读者聚合。 证据：[`14-community/12-popular-highlights.png`](14-community/12-popular-highlights.png)、[`14-community/19-return-to-popular-highlights.png`](14-community/19-return-to-popular-highlights.png)。
- **当前fork**：只有自己的annotation，没有跨用户计数或排行榜。
- **差异 / 要求**：不把自己的笔记按数量排序后叫“热门划线”；社区热门数据服务在现范围内不做。

### S05 [微信读书独有] 热门片段跳转与上一句/下一句黑条

- **微信读书**：点热门条目回正文，黑条包含关闭、上一句、下一句和列表入口。 证据：[`14-community/13-popular-highlight-jump.png`](14-community/13-popular-highlight-jump.png)、[`14-community/19-return-to-popular-highlights.png`](14-community/19-return-to-popular-highlights.png)。
- **当前fork**：本地有目录/搜索/笔记定位和位置栈，但没有热门片段序列；通用跳转导航可复用G06结构。
- **差异 / 要求**：微信热门数据链路不做。若后续做自己的笔记逐条浏览，是独立的可做本地功能，不能宣称已经具备微信热门路径。

### S06 [微信读书独有] 书友想法显示开关与正文虚线

- **微信读书**：开启后正文出现虚线，气泡按钮变隐藏书友想法；随后本次已恢复隐藏。 证据：[`14-community/15-show-reader-thoughts.png`](14-community/15-show-reader-thoughts.png)、[`14-community/20-hide-reader-thoughts-action.png`](14-community/20-hide-reader-thoughts-action.png)。
- **当前fork**：没有其他用户对原文范围的云想法、可见性或下载同步，只有自己的本地标记。
- **差异 / 要求**：不把本地划线误用成书友虚线，也不画无法取得内容的开关；这不是简单的划线样式差异。

### S07 [微信读书独有] 片段想法卡片流与参与讨论

- **微信读书**：点虚线显示引用及多位读者的想法卡、赞和评论；点写想法带入引用，本次只查看后取消。 证据：[`14-community/16-reader-thoughts-for-passage.png`](14-community/16-reader-thoughts-for-passage.png)、[`14-community/17-community-thought-editor.png`](14-community/17-community-thought-editor.png)。
- **当前fork**：本地可保存带引用的想法，但没有云讨论列表、点赞、回复或发布身份。
- **差异 / 要求**：本地编辑布局复用J01；社区列表及公开发表链路不实现，不能把本地保存按钮连接成假公开发表。

### S08 [微信读书独有] 微信账号、微信文集及退出登录

- **微信读书**：个人页有微信身份、微信文集/微信读书阅读器等入口，设置末尾有退出登录；本次未进入或退出。 证据：[`13-reading-preferences/01-profile-entry.png`](13-reading-preferences/01-profile-entry.png)、[`13-reading-preferences/04-settings-last-page.png`](13-reading-preferences/04-settings-last-page.png)。
- **当前fork**：我的页是本地统计与工具，没有微信登录。KOSync/Calibre等各有独立账号或连接，不能共用微信退出语义。
- **差异 / 要求**：不照抄微信账号、会员/余额、文集与退出登录；本地关于/版本更新可以继续使用自己的来源，不冒充微信服务。

## T. 共用视觉、证据边界与已有能力的保留（横跨16目录）

当前代码落点：[`DESIGN.md`](../../../DESIGN.md)、[`CONTEXT.md`](../../../CONTEXT.md)、[`design/demo/index.html`](../../../design/demo/index.html)、[`frontend/ui/palette.lua`](../../../frontend/ui/palette.lua)、[`frontend/ui/widget/bottomsheet.lua`](../../../frontend/ui/widget/bottomsheet.lua)、[`frontend/ui/widget/einkcontrols.lua`](../../../frontend/ui/widget/einkcontrols.lua)、[`frontend/ui/widget/container/alphacontainer.lua`](../../../frontend/ui/widget/container/alphacontainer.lua)、[`frontend/apps/shelf/fileschooser.lua`](../../../frontend/apps/shelf/fileschooser.lua)、[`frontend/apps/shelf/meview.lua`](../../../frontend/apps/shelf/meview.lua)、[`frontend/apps/opds/booksourceview.lua`](../../../frontend/apps/opds/booksourceview.lua)。

### T01 [可做] 黑白结构与原型/生产颜色的区分

- **微信读书**：应用以白底黑字、黑色线框、灰色轨道和黑底选中态为主；ADB仍保存彩色封面，不能代表实际面板灰阶。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`01-reader-navigation/01-toolbars.png`](01-reader-navigation/01-toolbars.png)、[`02-typography/01-font-panel.png`](02-typography/01-font-panel.png)、[`07-selection-and-lookup/01-english-word-selected.png`](07-selection-and-lookup/01-english-word-selected.png)。
- **当前fork**：生产Palette已用纯白/黑及16级灰度；demo/DESIGN用米白与近黑模拟屏幕，不能据demo十六进制值说真机底色偏黄。
- **差异 / 要求**：保留生产灰度方案，按每种控件校准灰度角色和描边；不要把截图彩色封面作为新增彩色UI要求，也不要无依据更改整套灰阶值。

### T02 [可做] 底部面板边界、返回与关闭方式

- **微信读书**：常用面板多为横向直线边界，底部工具栏/返回继续存在；字体右上是段落入口，不是统一关闭X。 证据：[`02-typography/01-font-panel.png`](02-typography/01-font-panel.png)、[`02-typography/06-paragraph-indent.png`](02-typography/06-paragraph-indent.png)、[`03-progress/01-progress-panel.png`](03-progress/01-progress-panel.png)、[`03-progress/03-auto-page-turn-settings.png`](03-progress/03-auto-page-turn-settings.png)。
- **当前fork**：BottomSheet统一16dp顶圆角、1dp边框、54dp标题及右上X，开面板隐藏工具栏；并不等于每张参考图都这样。
- **差异 / 要求**：按功能选择面板结构，不能用一个现有sheet皮肤套全部路径；统一返回层级和可达停止动作，而非强行统一所有标题栏。

### T03 [可做] 确认层与被压淡的背景

- **微信读书**：删除/移出确认自底部出现，原背景被压淡，操作分整行；想法编辑背景也压淡，普通排版预览上方正文则保持可读。 证据：[`05-bookmarks/06-bookmark-delete-confirmation.png`](05-bookmarks/06-bookmark-delete-confirmation.png)、[`06-notes/03-existing-note-long-press.png`](06-notes/03-existing-note-long-press.png)、[`07-selection-and-lookup/04-write-thought-editor.png`](07-selection-and-lookup/04-write-thought-editor.png)、[`07-selection-and-lookup/11-test-thought-delete-confirmation.png`](07-selection-and-lookup/11-test-thought-delete-confirmation.png)、[`10-conversion-and-book-actions/03-bookshelf-action.png`](10-conversion-and-book-actions/03-bookshelf-action.png)、[`11-handwriting/10-test-handwriting-delete-confirmation.png`](11-handwriting/10-test-handwriting-delete-confirmation.png)。
- **当前fork**：共用BottomSheet scrim主要拦截点击且透明；原ConfirmBox/通知等控件外观混用，新卡片没有同款删除层。
- **差异 / 要求**：为确认和编辑场景定义灰白遮罩及分行操作，使用已有绘制/Alpha能力；不要给所有排版预览统一盖灰，也不要让触摸穿透到正文。

### T04 [可做] 分页器、返回与边界状态的统一

- **微信读书**：右下连体胶囊含上下方向的翻页箭头，左下返回，边界按钮变灰；截图列表不在中间固定显示n/N。 证据：[`04-contents-and-search/01-contents.png`](04-contents-and-search/01-contents.png)、[`06-notes/02-notes-next-page.png`](06-notes/02-notes-next-page.png)、[`06-notes/05-notes-last-page.png`](06-notes/05-notes-last-page.png)、[`08-listening/10-episode-list-bottom.png`](08-listening/10-episode-list-bottom.png)、[`13-reading-preferences/04-settings-last-page.png`](13-reading-preferences/04-settings-last-page.png)。
- **当前fork**：已有共享EinkControls.Pager及ShelfWidgets.Pager，常是分开的左右按钮加居中页码；不同旧菜单还各有布局。
- **差异 / 要求**：统一新全屏列表和书架底部控件位置、轮廓及禁用反馈，复用分页逻辑；方向图标对应列表翻页，不改正文左右翻页含义。

### T05 [待定] 刷新类型、动画、触摸延迟与物理灰阶验收

- **微信读书**：PNG能证明静态布局和少量等待态，不能证明用了哪种刷新波形、动画时长、残影或真实笔延迟。 证据：[`01-reader-navigation/02-tap-next-page.png`](01-reader-navigation/02-tap-next-page.png)、[`02-typography/02-font-size-increased.png`](02-typography/02-font-size-increased.png)、[`03-progress/08-progress-jump-loading.png`](03-progress/08-progress-jump-loading.png)、[`07-selection-and-lookup/01-english-word-selected.png`](07-selection-and-lookup/01-english-word-selected.png)、[`11-handwriting/02-test-stroke-and-eraser-selected.png`](11-handwriting/02-test-stroke-and-eraser-selected.png)。
- **当前fork**：当前模块明确发ui/fast/partial刷新，系统可能按全刷频率升级；历史#1也列出真机仍待验收项。
- **差异 / 要求**：本轮只定静态/路径需求，刷新性能要在fork真机走同样动作验收；不能从微信PNG声称“只能刷此矩形/绝不全刷”，也不把历史测试通过等同新布局已验收。

### T06 [待定] 笔记术语与当前规范的整体冲突

- **微信读书**：统一“笔记”列表包括想法、划线、书签，统计卡与空状态也这样表述。 证据：[`05-bookmarks/04-bookmark-in-notes.png`](05-bookmarks/04-bookmark-in-notes.png)、[`05-bookmarks/05-bookmarks-and-highlights-filter.png`](05-bookmarks/05-bookmarks-and-highlights-filter.png)、[`06-notes/06-empty-notes-completed-book.png`](06-notes/06-empty-notes-completed-book.png)。
- **当前fork**：CONTEXT明确笔记不包括书签，定义目录抽屉；DESIGN和demo进一步规定黑气泡、四格底栏、三档排版，与实机不符。
- **差异 / 要求**：此清单将实机事实与现状并列，不暗改既有规范；实施前需一次性决定术语和结构迁移，更新文档/demo/调用入口/测试的同一口径。

### T07 [待定] 文件页与书源扩展的保留

- **微信读书**：样本书架有导入/选择，没有KOReader文件页或自配OPDS入口；微信云下载也不是自配书源。 证据：[`00-entry/01-bookshelf.png`](00-entry/01-bookshelf.png)、[`10-conversion-and-book-actions/04-offline-download-action.png`](10-conversion-and-book-actions/04-offline-download-action.png)。
- **当前fork**：#10已实现面包屑、文件夹/文件分页、长按更多；#24及后续#27已有书源网格、搜索、分类、格式下载、认证/缓存/错误处理。
- **差异 / 要求**：这些已合并能力保留，不自动降级到旧界面。需确定在新首页的入口；书源完整需求沿用#24及已合并修正，不把未拍到的微信路径补造为同款要求。

### T08 [待定] 我的页周统计、生词本与同步传书的新位置

- **微信读书**：微信个人页以身份、累计时长及服务入口为主，没有这次拍到的KOReader周图/本地工具矩阵。 证据：[`13-reading-preferences/01-profile-entry.png`](13-reading-preferences/01-profile-entry.png)、[`13-reading-preferences/02-settings.png`](13-reading-preferences/02-settings.png)。
- **当前fork**：#11已有真实周图、连续天数、今年完成、全局笔记、生词本、KOSync/Calibre/云存储/书源；子页保留底栏。
- **差异 / 要求**：需决定这些本地扩展继续在首页、进二级页还是设置；不能因参考图无入口就删除数据或把KOSync当微信账号。布局决策待定，能力本身已经实现。

### T09 [待定] 亮度、个人书评、导出与高级排版的次级路径

- **微信读书**：这批主要阅读画面没有直接展示亮度面板、笔记导出、三种样式/高级排版或本地个人星级入口；全站推荐卡不等于个人评价。 证据：[`01-reader-navigation/01-toolbars.png`](01-reader-navigation/01-toolbars.png)、[`12-book-ending/04-book-end.png`](12-book-ending/04-book-end.png)、[`07-selection-and-lookup/14-highlight-actions.png`](07-selection-and-lookup/14-highlight-actions.png)。
- **当前fork**：#4亮度/更多、#5高级排版、#6三样式、#8导出、原BookStatusWidget个人星级/书评都已有能力；原版菜单始终可达。
- **差异 / 要求**：需在复刻主路径之外安排可达入口并保留原数据，不增加无实机证据的“微信同款”按钮；特别不能用群体推荐值替换个人评价。

### T10 [可做] 本地化、格式与原设置兼容

- **微信读书**：参考是中文、触屏、竖屏的三个流式书样本，不涵盖PDF、其他语言和设备键。 证据：[`01-reader-navigation/01-toolbars.png`](01-reader-navigation/01-toolbars.png)、[`02-typography/01-font-panel.png`](02-typography/01-font-panel.png)、[`04-contents-and-search/01-contents.png`](04-contents-and-search/01-contents.png)、[`13-reading-preferences/02-settings.png`](13-reading-preferences/02-settings.png)。
- **当前fork**：当前新模块有gettext、触屏替换挂钩、版式书排版回退、原版全部设置及现有按键处理。
- **差异 / 要求**：将图示和中文作为此机目标，同时保留本地化、PDF与原菜单回退、实体键；不能因样本范围窄而缩减已支持能力。全新布局需验证现有调用者，而非仅修改demo。

## 截图覆盖检查与实施边界

下表把16个截图目录全部映射到需求编号；185张PNG均至少在一条需求的证据中引用。重复的恢复/清理截图用于状态一致性要求，不额外发明功能。所有截图路径、源代码链接和编号在生成后做了存在性核对。

| 原截图目录 | 张数 | 对应需求 |
| --- | ---: | --- |
| [00-entry](00-entry/) | 3 | A01, A02, A03, A04, A05, A06, A07, A08, A09, A10, A11, B01, B02, B05, B06, O03, R04, T01, T07 |
| [01-reader-navigation](01-reader-navigation/) | 5 | B03, B04, C01, C02, C03, C05, T01, T05, T09, T10 |
| [02-typography](02-typography/) | 15 | B06, C04, D01, D02, D03, D04, D05, D06, D07, D08, D09, D10, R03, T01, T02, T05, T10 |
| [03-progress](03-progress/) | 11 | C04, C05, E01, E02, E03, E04, E05, E06, F01, F02, F03, F04, T02, T05 |
| [04-contents-and-search](04-contents-and-search/) | 9 | G01, G02, G03, G04, G05, G06, G07, G08, N04, T04, T10 |
| [05-bookmarks](05-bookmarks/) | 7 | G08, H01, H02, H03, H04, H05, I07, T03, T06 |
| [06-notes](06-notes/) | 7 | E02, E06, H05, I01, I02, I03, I04, I05, I06, I07, P04, T03, T04, T06 |
| [07-selection-and-lookup](07-selection-and-lookup/) | 25 | A09, J01, J02, J03, J04, J05, J06, K01, K02, K03, K04, K05, K06, K07, K08, L01, L02, L03, L04, L05, L06, L07, M01, O01, T01, T03, T05, T09 |
| [08-listening](08-listening/) | 24 | A01, A03, G06, M01, M02, M03, M04, M05, M06, M07, M08, M09, O03, T04 |
| [09-images](09-images/) | 3 | N01, N02, N03, N04 |
| [10-conversion-and-book-actions](10-conversion-and-book-actions/) | 4 | C02, O01, O02, O03, O04, O05, T03, T07 |
| [11-handwriting](11-handwriting/) | 8 | I07, P01, P02, P03, P04, P05, T03, T05 |
| [12-book-ending](12-book-ending/) | 4 | Q01, Q02, Q03, Q04, Q05, T09 |
| [13-reading-preferences](13-reading-preferences/) | 4 | R01, R02, R03, R04, R05, R06, R07, S08, T04, T08, T10 |
| [14-community](14-community/) | 14 | C03, J01, J02, Q05, S01, S02, S03, S04, S05, S06, S07 |
| [15-supplement](15-supplement/) | 42 | A04, A05, A06, A07, A08, A09, A11, B05, B06, E05, K04, K08, N04, Q01, Q02, R02 |

此清单不把样本以外的功能定为缺陷：PDF专用排版、横屏、非中文本地化、实体翻页键、原手势/高级设置等继续保留。微信账号、书城授权、云语音与跨读者社区只作设计参考；通用听书、繁简、自由手写因后端/平台范围未定而单列待定。

本轮仅补充微信读书实机证据和文档，未开issue、未改fork代码，也未重新跑代码测试或宣称fork新布局已真机验收。两条测试划线已删、笔记恢复42条，左侧下一页已关回，阅读段落已恢复；首页“审判”搜索历史未找到单条删除，未清空原有历史，阅读时长/最近打开记录也未回滚，详见README恢复记录。静态截图无法证明刷新波形、动效时长与触摸延迟；这些应在后续实际实现后，用同书同操作的fork截图和真机体验验收。
