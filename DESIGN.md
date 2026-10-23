---
name: KOReader e-ink redesign
description: KOReader re-cut in WeChat Read e-ink grammar; ink on paper, 1px rules, one bottom sheet, fewer refreshes.
colors:
  paper: "#F1F1EC"
  ink: "#151515"
  ink-2: "#565653"
  ink-3: "#9A9A96"
  rule: "#C4C4BF"
  mark: "#C6C6C1"
  bubble-rule: "#4A4A47"
  marker-on-ink: "#8E8E8A"
  cover-stock: "#E2E2DD"
  cover-tint: "#BBBBB6"
  cover-gray: "#8B8B87"
typography:
  reading:
    fontFamily: "Noto Serif SC, Songti SC, STSong, SimSun, serif"
    fontSize: "19px"
    fontWeight: 400
    lineHeight: 1.8
  reading-latin:
    fontFamily: "Noto Serif, Georgia, Noto Serif SC, serif"
    fontSize: "19px"
    fontWeight: 400
    lineHeight: 1.8
  reading-chapter:
    fontFamily: "Noto Serif SC, Songti SC, STSong, SimSun, serif"
    fontSize: "1.5em"
    fontWeight: 700
    lineHeight: 1.35
  headword:
    fontFamily: "Noto Serif SC, Songti SC, STSong, SimSun, serif"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: 1.2
  headline:
    fontFamily: "Noto Sans SC, PingFang SC, Hiragino Sans GB, Microsoft YaHei, sans-serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.3
  title:
    fontFamily: "Noto Sans SC, PingFang SC, Hiragino Sans GB, Microsoft YaHei, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Noto Sans SC, PingFang SC, Hiragino Sans GB, Microsoft YaHei, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.45
  excerpt:
    fontFamily: "Noto Serif SC, Songti SC, STSong, SimSun, serif"
    fontSize: "14.5px"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Noto Sans SC, PingFang SC, Hiragino Sans GB, Microsoft YaHei, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  caption:
    fontFamily: "Noto Sans SC, PingFang SC, Hiragino Sans GB, Microsoft YaHei, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.45
    fontFeature: "tnum"
  micro:
    fontFamily: "Noto Sans SC, PingFang SC, Hiragino Sans GB, Microsoft YaHei, sans-serif"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.45
rounded:
  hairline: "2px"
  cover: "3px"
  badge: "4px"
  card: "10px"
  tile: "12px"
  sheet: "16px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "18px"
  gutter: "24px"
  touch: "44px"
  row: "56px"
components:
  chip:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 13px"
    height: "30px"
  chip-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.pill}"
  button-outline:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "0 16px"
    height: "40px"
  button-solid:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.pill}"
    padding: "0 16px"
    height: "40px"
  segmented:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    height: "38px"
  segmented-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  searchfield:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink-2}"
    rounded: "{rounded.pill}"
    padding: "0 14px"
    height: "40px"
  sheet:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sheet}"
    padding: "0 24px 20px"
  selection-bubble:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.card}"
    height: "44px"
  list-row:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    padding: "8px 0"
    height: "56px"
  tabbar:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink-2}"
    typography: "{typography.micro}"
    height: "56px"
  reader-toolbar-bottom:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    height: "76px"
  pager-button:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    width: "44px"
    height: "32px"
  toast:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.pill}"
    padding: "10px 18px"
---

# Design System: KOReader e-ink redesign

Scope: this system governs everything drawn inside the simulated e-ink screen (`.screen` and its descendants) of `design/demo/index.html`. The desk, bezel and control column around the device are demo chrome and are out of scope (see the end of Layout). All sizes are in dp: 1 CSS px in the prototype equals 1 dp, which KOReader produces with `Screen:scaleBySize()`. KOReader's existing token home is `frontend/ui/size.lua`, which covers borders, margins, paddings and radii. Colors and type sizes have no tokens there yet, and porting this system means adding them.

## Overview

**Creative North Star: "Ink on Paper, One Sheet at a Time"**

The page owns the screen. Chrome appears only when asked for: a center tap brings a calm black-on-paper toolbar, and every adjustment lives in one bottom sheet that rises over the page. The world is a paper ground and an ink black, with grays only where they carry a job: secondary text, dividers, disabled states and the marker highlight. Structure comes from 1px ink rules and sheet edges, never from shadow or motion. WeChat Read's e-ink edition is the pinned look and interaction model; deviating from it is a defect unless KOReader has a capability with no WeChat Read equivalent.

Density is calm and touch-first. Targets are at least 44dp, rows are 56dp, and the screen gutter is 24dp. Long lists paginate with a pager instead of scrolling, because scrolling on e-ink means a repaint storm. Every interaction is designed around the area it repaints and the KOReader refresh type it needs (partial, ui, fast, full). Only `full` flashes.

Night mode is a pixel inversion of the whole screen, the same as KOReader's. There is no second palette.

**Key Characteristics:**
- Paper ground, ink black, grays only for secondary text, rules, disabled states and highlights; monochrome is a confirmed constraint
- 1px ink rules and 1.5px ink outlines carry all structure; no shadows anywhere
- Black-filled pill is the selected state for chips and segmented controls
- Solid black selection bubble with paper labels
- Bottom sheets with a 1px ink border and 16dp top corners hold every adjustment
- Paginated lists with a pill pager; no scrolling surfaces
- Line icons with the label under the icon in tab bars and toolbars
- Typographic grayscale covers when a book has no cover image
- Every interaction maps to one KOReader refresh type

## Colors

A warm-neutral grayscale that quantizes cleanly onto a 16-level panel. The slight warmth of paper is a screen simulation; on device each value maps to its nearest Blitbuffer gray step.

### Primary
- **Ink** (ink): All primary text, icon strokes, structural rules (tab bar, toolbars, sheet and drawer edges, nav bar, group headers), interactive outlines, and every selected fill: chips, segments, the solid button, the selection bubble, the toast, the dog-ear bookmark and the text-selection highlight.

### Neutral
- **Paper** (paper): The screen ground and the fill behind every sheet, drawer, toolbar and subpage. It is also the text color on ink fills.
- **Pencil Gray** (ink-2): Secondary text such as meta lines, list sub-lines, values, sheet row labels, inactive tab labels, page header and footer, and placeholders.
- **Faded Gray** (ink-3): Disabled controls, chevrons, unavailable TOC entries and fine print.
- **Rule Gray** (rule): 1px dividers between list rows and the disabled outline of pager and stepper buttons. Also the resting border of the font and action tile cards.
- **Marker Gray** (mark): The marker highlight fill behind reading text and its swatch in notes.
- **Bubble Rule** (bubble-rule): Dividers inside the black selection bubble.
- **Marker-on-Ink** (marker-on-ink): The marker swatch shown on the black bubble's style row.

### Cover grays
Generated typographic covers draw from three extra fills: **Cover Stock** (cover-stock), the light card ground for the frame and stripe covers; **Cover Tint** (cover-tint), the field behind the oversized glyph on split covers; and **Cover Gray** (cover-gray), the mid-tone block cover. Ink and paper complete the set. These grays appear only on covers.

### Named Rules
**The Monochrome Rule.** Color never carries meaning. Every state reads in black, white and gray, because every target panel is monochrome.

**The Job-Only Gray Rule.** A gray must do a named job (secondary text, divider, disabled, highlight). Never introduce a gray for mood or depth.

## Typography

**UI Font:** Noto Sans SC (with PingFang SC, Hiragino Sans GB, Microsoft YaHei)
**Reading Font:** Noto Serif SC (with Songti SC, STSong, SimSun); Noto Sans SC is the user-selectable alternative
**Latin reading faces:** Noto Serif, with Noto Sans as the sans option. Both are KOReader-bundled faces, so English quotes do not set full-width.

**Character:** A neutral CJK sans for every control, and a book serif for everything that is the book's own words. That covers the page, excerpts in notes and search results, dictionary headwords, and cover titles.

### Hierarchy
- **Reading** (400, user-set 15–28dp in steps 15/16/17/18/19/20/22/24/26/28, default 19; line-height 1.55 / 1.8 / 2.1, default 1.8): Justified body text. Chinese paragraphs get a 2em first-line indent and a 0.45em paragraph gap. English paragraphs get a 1.5em indent, no gap, and automatic hyphenation.
  - *KOReader port:* crengine sets line spacing as a percentage of the face's own line height, which is about 1.45em for the CJK faces. The three steps are therefore 105 / 125 / 145 % (紧凑 / 标准 / 宽松). On the CJK sans this measures about 1.55 / 1.8 / 2.1em; Latin faces have a shorter natural line height (about 1.36em), so they come out slightly tighter. Font sizes are KOReader dp (`Screen:scaleBySize`), the same numbers as above.
  - *KOReader port:* the serif and sans cards follow the book's typography language. CJK books get 思源宋体 (Source Han Serif / Noto Serif CJK, not bundled) or 思源黑体 (the bundled Noto Sans CJK SC). Other books get the bundled Noto Serif or Noto Sans, so English quotes and apostrophes never set full-width. When the serif is missing, the card is grayed and marked 未安装. As in upstream ReaderFont, only the first face of a .ttc collection is recognized. Books without a usable language tag (txt, `und`, missing) follow the UI language. Tapping it, or opening a CJK book for the first time (once per install), says where to put the font files and uses 思源黑体.
- **Reading chapter** (700, 1.5em, 1.35): Chapter titles in the flow, left-aligned and balanced.
- **Headword** (serif 700, 26dp, 1.2): Dictionary sheet entry word.
- **Headline** (700, 22dp, 1.3): Top-level page titles such as 文件 and 我的.
- **Title** (700, 16dp): Nav bar titles and sheet headers. Drawer book titles are 17dp.
- **Body** (400, 15dp, 1.45): The screen default and the first line of list rows.
- **Excerpt** (serif 400, 14.5dp, 1.6–1.65): Quoted book text in notes and search results, clamped to 2–3 lines.
- **Label** (400–500, 13–14dp): Chips, segments, buttons, book titles under covers (13/500), and bubble actions (14).
- **Caption** (400, 12dp, tabular figures): Status bar, page header and footer, list sub-lines, group headers and progress meta.
- **Micro** (11dp): Tab bar labels, tags and day labels.

### Named Rules
**The Book Voice Rule.** Serif marks the book's own words. Controls never use the serif, and book text never uses the UI sans unless the reader chose the sans reading font.

**The Tabular Rule.** Every number that updates in place (page counts, percentages, time, battery, pager) uses tabular figures, so a partial refresh does not shift its neighbours.

## Layout

The screen is laid out at 1:1 dp on three reference panels: 6" at 536 × 724, 7" at 632 × 840 (the default) and 10.3" at 936 × 1248. Layouts scale by proportion, not by separate designs.

- **Fixed bands.** The 24dp status bar is always at the top. Library views keep a 56dp tab bar at the bottom. The view between them is a flex column.
- **Gutter.** 24dp on the left and right of every list, grid and sheet.
- **Cover grid.** Columns are computed per panel with space-between distribution, 18dp row gap and 3:4 covers. Title and 读到 x% sit under each cover.
- **Reading page.** The page header sits at 14dp and the text viewport runs from 44dp to 42dp above the bottom. Side margins are 18 / 28 / 44dp (narrow / standard / wide). Panels wider than 800dp add 72dp per side to keep a line near 38 CJK characters. Pages are columns, never scroll.
  - *KOReader port:* KOReader's dp is proportional, not physical: `scaleBySize` is min(w, h) / 600, unless the user overrides the DPI. Every portrait panel is therefore 600dp wide, and font size scales with it, so 6", 7" and 10.3" set the same line length. The literal "+72dp above 800dp" rule would cut a 10.3" line to about 21 characters. The port instead widens each side by max(0, (W − 2·margin − 38·font size) / 2) dp, recomputed whenever the panel changes the size or the margin step, when a book opens, and on rotation. This changes nothing in portrait; it only applies in landscape or with a DPI override, where several steps can widen to the same margins. The chosen step is therefore saved per book (`typeset_margin_step`) instead of being read back from the margins. It is forgotten when the margins are set some other way (the original bottom bar, gestures). The cap is skipped in two-column mode.
  - *KOReader port:* the page header is the chapter title (the book title when there is no TOC), drawn at 14dp, left-aligned with the text, 12dp caption in pencil gray, truncated to the text width. It is drawn only when the top margin holds it with a 4dp gap, so it never overlaps the text. It is hidden in scroll mode, when crengine's own top status bar is on, and for fixed-layout books. The design defaults are top margin 44dp, font 19, line spacing 125 % and side margin 28dp; they are written once as global defaults when a book opens with the panel, never over the user's own (whether in the reader settings or customized in defaults.lua).
- **Pagination over scrolling.** Every list (shelf, files, TOC, notes, search, settings) fills its region and pages with a 44dp pager band: a pill back button, "n / N" and a pill forward button. Overflow is hidden.
- **Overlay stack.** In order: page, toolbars, scrim, drawer or sheet, subpage, tap-zone overlay, bubble, toast. A sheet opened from a full-screen subpage (书源's long-press, 分类浏览, edit and menu sheets) stacks above that subpage, with its scrim just below it. The drawer opens from the left at min(86%, 560dp). Sheets rise from the bottom, up to 84% of the screen height.
- **Rhythm.** Gaps step 4 / 8 / 12 / 18 / 24; 10 and 14 are used for intra-component gaps.

**The Proportion Rule.** One design from 6" to 10.3". Change columns and margins with the panel and keep the component sizes.

**Out of scope: demo chrome.** The desk background, dark bezel, 292px control column (device size segment, refresh-region and night switches, refresh log, jump list, context path in monospace) and the orange signal color `#D9481F` exist only to present and instrument the prototype. The orange belongs only to the refresh-region overlay (2px dashed outline plus type label) and the control-column switches. The warm front-light tint is a multiply overlay that simulates the light, not pixels. None of these are product tokens.

## Elevation & Depth

Flat by construction. E-ink cannot render soft shadows, and the system does not fake them. Depth is conveyed by edges and by occlusion only. A sheet is a paper plane with a 1px ink border drawn over the page. Toolbars are paper bands with a 1px ink rule on their inner edge. The drawer has a 1px ink right edge. The one exception to "edges only" is the black bubble, which separates by solid fill.

**The Edge, Not Shadow Rule.** Separate surfaces with a 1px ink rule or a sheet edge. Never use a drop shadow, blur or translucent scrim tint. Scrims exist only to catch taps and are fully transparent.

**The No-Motion Rule.** Nothing animates on the product surface. State changes are a repaint of a named region with a named refresh type.

## Shapes

Two families. **Pills** (radius = half the height) are for everything tappable that sits on a line of controls: chips (30dp), search fields (40–42dp), segmented controls and steppers (38dp), buttons (40dp), pager buttons (44 × 32dp), toggles and the toast. **Soft rectangles** are for containers: font cards at 10dp, the selection bubble at 10dp, the note textarea at 10dp, action tiles at 12dp, and sheet top corners at 16dp. Small square-ish marks are badges (format badge and part-of-speech tag at 4dp) and covers (3dp, 2dp in the drawer).

Border weights form a three-step ladder that maps onto `size.lua`:
- **1px** (`Size.border.default`): structural rules and row dividers, chips, pager buttons, tags.
- **1.5px** (`Size.border.button` / `window`): interactive outlines such as the search field, segmented controls, steppers, outline buttons, toggles and the textarea.
- **2px** (`Size.border.thick`): selected font card and tap-zone outlines.

`size.lua` radii (default 2, window 7, button 7) do not cover the pill or the 16dp sheet; they need new entries.

## Components

### Buttons
Quiet outlines that turn solid for the one committing action.
- **Shape:** pill, 40dp tall, 0 16dp padding, 14dp label, icon gap 6dp.
- **Outline:** paper fill, 1.5px ink border, ink label.
- **Solid:** ink fill, paper label. Use one per sheet, for the commit (保存, 搜索 go button).
- **Disabled:** border to rule gray, label to faded gray.
- **Focus:** 2px ink outline inset 3px. No hover state on device.

### Chips
- **Style:** 30dp pill, 1px ink border, 13dp label with an optional count at 75% opacity, 8dp apart.
- **State:** selected is a solid ink fill with paper text. Use them for single-choice filters (全部 / 在读 / 未读 / 读完).

### Segmented control
A 38dp pill with a 1.5px ink border. Segments are split by 1px ink rules and the selected segment is ink-filled with paper text. It is the standard single-choice control inside sheets (line spacing, margins, sort). In sheets it sits in a row that has a 56dp column for a gray label on the left.

### Stepper and tick scale
Two 44 × 38dp pill buttons, with a small and a large serif "A", flank a tick track. The track is a 1.5px ink line with 7dp hollow dots. Passed ticks fill ink, and the current tick is a 16dp solid dot. Font size uses this control. Each step repaints the page with a partial refresh.

### Cards / Containers
- **Font and action tiles:** 1px rule-gray border at rest. The selected tile turns to a 2px ink border. Font tiles are 66dp at 10dp radius; action tiles are 84dp at 12dp radius, with icon over label.
- **Background:** paper.
- **Shadow Strategy:** none (see Elevation & Depth).

### Inputs / Fields
- **Search field:** 40–42dp pill, 1.5px ink border, search icon, 15dp input, pencil-gray placeholder, and an inset solid 32dp go pill.
- **Note textarea:** 1.5px ink border, 10dp radius, 12dp padding, 15dp at line-height 1.6, no resize.
- **Toggle:** 42 × 26dp pill. When off it has a 1.5px ink outline and an ink knob. When on it is ink-filled with a paper knob.
- **Labelled field** (forms in sheets, such as 添加书源): a 13dp `ink-2` label column beside a 40dp pill input with a 1.5px ink border, 15dp text and a pencil-gray placeholder. Rows are 52dp minimum. The label column is 92dp, wider than a sheet row's 56dp, because labels such as "Client Secret" must fit on one line. Optional groups sit under a 12dp gray group header. A form commits with one solid button, disabled (rule border, faded label) until its required fields are filled.

### Navigation
- **Tab bar** (书架 / 文件 / 我的): 56dp, with a 1px ink rule on top. Each tab is a line icon over an 11dp label. Inactive tabs are pencil gray. The current tab is ink and bold, and its icon stroke thickens from 1.7 to 2.2.
- **Nav bar** (subpages): 52dp with a 1px ink bottom rule. A 52dp back column sits on the left, with a centered 16dp bold title.
- **Drawer tabs** (目录 / 书签 / 笔记): equal columns over a 1px ink rule. The selected tab is ink, bold, with a 3px ink underline across the middle 40%.
- **List row:** at least 56dp, with a 1px rule-gray bottom divider. It has a 15dp first line, a 12dp gray second line, an optional right-hand value and a faded chevron. Group headers are 12dp gray over a 1px ink rule.

### Reader toolbars
A center tap brings two paper bands. The top bar is 56dp (back, then bookmark, search, more) with a 1px ink bottom rule. The bottom bar is 76dp with four equal cells, each a line icon over a 12dp label: 目录, 进度, 亮度, 字体. It has a 1px ink top rule. Both appear and hide with a `ui` refresh limited to their own rects.

### Bottom sheet
The single home for every adjustment. A paper plane with a 1px ink border and 16dp top corners, bleeding 1px past the screen edges. Content has 24dp side padding and 20dp at the bottom. The 54dp header holds a 16dp bold title and a close icon button. Rows are 52dp minimum. An optional link row at the foot has a 1px rule above it and a chevron. A sheet that only navigates (书源's 分类浏览) may lay its rows out in two columns with a 24dp gap; the current item is bold with a check mark instead of a chevron.

### Selection bubble
A solid ink 10dp-radius bar with paper labels, 44dp action cells (复制 / 划线 / 写想法 / 查询 / 搜索) separated by bubble-rule dividers, and a 7dp arrow pointing at the selection. On device the selection bubble's dividers are paper instead of bubble-rule: the bubble shows with a `fast` refresh, which renders only black and white, and a bubble-rule gray would come out wrong. The highlight bubble keeps bubble-rule, as it refreshes with `ui` for its gray marker swatch. When neither above nor below the selection has room, the bubble overlays the selection without the arrow. A second row carries highlight styles. The selected style is a 2dp paper inset ring. Text selection itself is ink fill with paper text.

### Highlights
Three styles, all monochrome: **marker** (marker-gray fill), **line** (2dp ink underline offset 0.3em) and **wave** (1.3dp wavy ink underline). A note adds a small ink note glyph after the highlight's last character.

### Typographic cover
Generated when a book has no cover. It is 3:4, 3dp radius, with a 1px 20%-ink hairline frame. Variants: **frame** (double-ruled border with a vertical CJK title), **band** (ink field, paper title, rule, author), **block** (cover-gray field, sans title), **split** (cover-tint top 60% with an oversized paper glyph) and **stripe** (2dp ink stripes behind a ruled cover-stock label). Titles use the reading serif; authors use the UI sans. On Latin titles the title size is capped by the longest word, so no word ever breaks or clips.
- **With a cover image:** a real cover (from the book, or an OPDS thumbnail) fills the same 3:4, 3dp frame, cropped to fill and quantized to 16 grays. For remote books the typographic cover stands in until the image arrives, and a page of images lands in one `ui` repaint of the grid (at most 3 s after the page; later images only go to the cache).
- **Download band:** while a remote book downloads, a 24dp paper band with a 1px ink top rule sits at the cover's foot, holding a 4dp ink-on-rule progress bar; the caption under the cover reads 下载中 n%. The cover itself is never tinted. Each progress tick repaints only the band and caption with `fast` (both are pure black and white); the band appearing or leaving over a gray cover is a `ui` repaint of the tile.
- **Downloaded mark:** a remote book already on the device carries a 13dp gray check before the first line of its title, the way WeChat Read marks local books; the caption under the title reads 读到 x% once the book is started, otherwise the author. A finished download only repaints its tile (`ui`); it never opens the book, so several downloads can run side by side. Tapping a marked tile opens the book.

### Pager and toast
The pager has 44 × 32dp pill buttons with a 1px ink border; disabled buttons go to the rule border and faded glyph. The page count sits between them in 13dp tabular figures. When a server has more pages than the device has fetched, the count reads "n / …" and the forward button stays enabled. While the next batch loads, both buttons disable and the count reads 取下一批…, a `fast` repaint of the pager band only. The toast is an ink pill with paper 14dp text, centered 96dp above the bottom, at most 84% wide.

### Loading, empty and error states
They sit in the region they replace (a grid, a list), never in a dialog, centred with 40dp above. In order: a 15dp bold ink line, a 14dp `ink-2` reason, an optional 12dp `ink-2` tabular line with the technical detail (HTTP 401 · host), then at most one outline button for the next step (重试, 编辑书源). Loading is the reason line alone (正在连接家里的 NAS…). The same block is the empty state of every list.

### Refresh mapping
Each interaction declares one KOReader refresh type and the smallest rect set it repaints:
- **partial:** page turns, reflow after type changes, jumps to a chapter, bookmark, note or search hit.
- **ui:** toolbars, sheets, drawers, tab switches, list pages and filters.
- **fast:** toggles, selection and bubble, bookmark dog-ear, hints.
- **full:** opening a book, returning to the shelf, night mode, and every 6th page turn to clear ghosting.

## Do's and Don'ts

### Do:
- **Do** separate surfaces with 1px ink rules and divide list rows with 1px rule gray.
- **Do** show single-choice selection as an ink-filled pill with paper text.
- **Do** put every reading adjustment in one bottom sheet with a 1px ink border and 16dp top corners.
- **Do** paginate lists with the pill pager and "n / N"; keep overflow hidden.
- **Do** put the label under the icon in tab bars and toolbars, with line icons at 1.7 stroke and 2.2 for the current tab.
- **Do** keep touch targets at 44dp or more and list rows at 56dp or more.
- **Do** use tabular figures for every number that updates in place.
- **Do** name the refresh type and repaint region for every new interaction; only `full` may flash.
- **Do** implement night mode as inversion of the whole screen, not as a second palette.

### Don't:
- **Don't** use color to carry meaning; the panels are monochrome.
- **Don't** use drop shadows, blur, gradients for depth, or tinted scrims.
- **Don't** animate anything on the product surface.
- **Don't** make lists scroll.
- **Don't** set controls in the serif, or book text in the UI sans unless the reader chose it.
- **Don't** bring the demo's orange signal color, desk grays or bezel into the product.
