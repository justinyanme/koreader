---
version: 1
slug: "design-demo-index-html"
primary_target: "design/demo/index.html"
related_targets: []
---

# Surface: KOReader e-ink redesign demo

Scope: single-file web prototype of the redesigned KOReader UI on an e-ink device. Mode: Operate.
Screens: 书架/文件/我的, reader page + tap toolbar, 目录/书签/笔记, 进度, 亮度, 排版 sheet, selection → 划线/写想法/查询, dictionary sheet, settings depth, 书源 (OPDS as a remote shelf: cover grid, long-press sheet, 分类浏览, search, manage/edit, network error states; spec justinyanme/koreader#24).
Audience: the fork owner, reading Chinese and English non-fiction EPUB on 6"/7"/10.3" monochrome Android e-ink and a Kindle.
Constraint: user pinned WeChat Read (微信读书) e-ink edition as the look and interaction model — "跟微信读书一样就行，不一样那就是有问题". Monochrome only. Everything must map onto KOReader's Lua widgets (no motion, explicit refresh regions).
Unresolved: exact WeChat Read e-ink screens unverified (no public screenshots fetched); calibrate against user's device screenshots.

## Direction contract

THESIS: KOReader re-cut in WeChat Read e-ink grammar — the page owns the screen, one center tap brings a calm black-on-paper toolbar, every adjustment lives in one bottom sheet. Refuses KOReader's icon-tab menu tree and dense config strip.

OWN-WORLD: Simulated e-ink paper ground, ink black, two grays at most. Separation by 1px ink rules and sheet edges, never shadows. Selected state is a black-filled pill with paper text. Selection bubble is solid black with paper labels. Noto Sans SC for UI, Noto Serif SC for reading. Line icons, one stroke weight, label under icon.

STORY: Open → shelf ordered by recency → tap cover → reading. Center tap shows the toolbar; 字体 changes type in one sheet; long-press gives 划线/写想法/查询; notes return in 目录's 笔记 tab. Advanced KOReader power stays reachable under 设置 › 全部设置.

FIRST VIEWPORT: Device frame (7" default) centred: search field top, cover grid (title + 读到 x% under each), tab bar 书架/文件/我的 at the bottom. Beside it, a quiet control column: device size, refresh-region toggle, night inversion, jump list of flows.

FORM: pinned by user, no concept-seed roll; Operate. Signature move: refresh-region overlay — each interaction outlines the area it repaints and names the refresh type, making "fewer refreshes" visible.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
