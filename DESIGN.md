---
name: KOReader e-ink redesign
description: KOReader re-cut to WeChat Read's e-ink edition as captured on a BOOX Leaf5; white paper, black ink, gray rules, full-screen lists, panels that keep the toolbars, fewer refreshes.
colors:
  paper: "#FFFFFF"
  ink: "#000000"
  ink-2: "#555555"
  ink-3: "#999999"
  rule: "#BBBBBB"
  mark: "#CCCCCC"
  tint: "#EEEEEE"
  hit: "#BBBBBB"
  cover-stock: "#DDDDDD"
  cover-tint: "#BBBBBB"
  cover-gray: "#888888"
typography:
  reading:
    fontFamily: "the reader's choice (see Typography)"
    fontSize: "19px"
    fontWeight: 400
    lineHeight: "125% of the face's line height"
  reading-chapter:
    fontFamily: "the reading face"
    fontSize: "1.5em"
    fontWeight: 700
    lineHeight: 1.35
  display:
    fontFamily: "Noto Serif CJK SC / Source Han Serif SC if installed, else Noto Serif with CJK falling back to Noto Sans CJK SC"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.2
  headword:
    fontFamily: "Noto Sans, Noto Sans CJK SC"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.3
  headline:
    fontFamily: "Noto Sans, Noto Sans CJK SC"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.3
  figure:
    fontFamily: "Noto Sans, Noto Sans CJK SC"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.2
    fontFeature: "tnum"
  excerpt:
    fontFamily: "Noto Sans, Noto Sans CJK SC"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: 1.45
  title:
    fontFamily: "Noto Sans, Noto Sans CJK SC"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Noto Sans, Noto Sans CJK SC"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "Noto Sans, Noto Sans CJK SC"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  caption:
    fontFamily: "Noto Sans, Noto Sans CJK SC"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.45
    fontFeature: "tnum"
rounded:
  tile: "8px"
  choice: "12px"
  popover: "13px"
  card: "14px"
  sheet: "16px"
  large: "19px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "18px"
  gutter: "22px"
  touch: "44px"
  band: "58px"
components:
  pill-outline:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "0 14px"
    height: "34px"
  searchfield:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "0 16px"
    height: "50px"
  segmented:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    height: "38px"
  segmented-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  chip:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 13px"
    height: "30px"
  track:
    backgroundColor: "{colors.mark}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    height: "33px"
  track-passed:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  font-tile:
    backgroundColor: "{colors.mark}"
    textColor: "{colors.ink}"
    rounded: "{rounded.tile}"
    height: "41px"
  font-tile-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "20px"
  selection-popover:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.popover}"
    height: "81px"
  confirm-layer:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    height: "58px"
  list-row:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    height: "53px"
  bottom-band:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    height: "58px"
  pager:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    width: "133px"
    height: "42px"
  search-bar:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.large}"
    height: "58px"
  toast:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.label}"
    rounded: "{rounded.tile}"
    padding: "0 18px"
    height: "47px"
---

# Design System: KOReader e-ink redesign

Scope: this system governs every screen the redesign draws in KOReader: the shelf, 书源, 我 and settings pages, the reader's chrome, full-screen pages, panels and overlays. The original KOReader screens behind the 原版入口 are out of scope.

**Source of truth.** The look and the interaction model come from WeChat Read's e-ink edition 2.1.2, captured on a BOOX Leaf5 (1264 × 1680 portrait) on 2026-10-23 in `design/references/weread-eink-leaf5-2026-10-23/`. The owner's rulings on that capture are in its `DECISIONS.md`, and the item list is in `REQUIREMENTS.md`. When sources disagree, the order is: the owner's rulings and `DECISIONS.md`, then the reference screenshots, then the notes in `REQUIREMENTS.md`, then this file, then the UI already merged. `design/demo/index.html` is the first-round prototype. It is not updated and it is no longer used to accept work.

**Units.** Sizes are KOReader dp, produced by `Screen:scaleBySize()`. A portrait panel is 600dp wide (see Layout), so on the Leaf5 1dp is 2.107px. The dp values below were measured from the reference screenshots at that ratio and rounded; the front matter writes them as px. When a value here and a screenshot disagree, the screenshot wins. KOReader's token homes are `frontend/ui/size.lua` (borders, margins, paddings, radii), `frontend/ui/palette.lua` (colors) and `frontend/ui/font.lua` (type roles).

## Overview

**Creative North Star: "Ink on Paper, Chrome on Request"**

The page owns the screen. A swipe up, or a tap in the middle, brings two quiet bands: a top bar of icons on the right and a bottom bar that starts with a back arrow. Typesetting and progress open as panels that slot between the page and the bottom bar, with the bottom bar still in place (and the top bar too, except over typesetting), so the reader can switch panels or leave without closing anything first. Everything longer than a panel (contents, notes, search results, lookup, settings) is a full-screen page with a back arrow at the bottom left and a joined pager at the bottom right. Overlays are white with an ink outline. The world is white paper and black ink. Grays appear only where they do a named job: rules, tracks, resting tiles, temporary marks, disabled states. Structure comes from 1dp rules and outlines, never from shadow or motion.

WeChat Read's e-ink edition is the pinned look and interaction model. A deviation is a defect, unless the owner ruled a local substitute (see Local substitutes) or KOReader has a capability that WeChat Read lacks, which then moves to a secondary entry instead of being dropped.

Density is calm and touch-first. Targets are at least 44dp. Long lists paginate instead of scrolling, because scrolling on e-ink means a repaint storm. Every interaction is designed around the area it repaints and the KOReader refresh type it needs (partial, ui, fast, full). Only `full` flashes.

Night mode is a pixel inversion of the whole screen, the same as KOReader's. There is no second palette.

**Key Characteristics:**
- Pure white paper and pure black ink; grays only for named jobs, from the panel's 16 levels
- 1dp gray rules for structure (bar edges, list dividers); 1dp ink outlines for what you touch or read as one unit (cards, pills, the popover)
- Ink fill marks the current choice: the font tile, the paragraph card, a toggle that is on, the passed part of a track
- Icons without labels in the tab bar and both reader toolbars
- Panels between the page and the bottom bar; the toolbars stay
- Full-screen pages with a bottom-left back arrow and a bottom-right joined pager; no scrolling surfaces
- A white selection popover with icons over labels, pointing at the selection
- Confirmations rise from the bottom over a washed-out, inert background
- Every interaction maps to one KOReader refresh type

## Colors

Every token is one of Blitbuffer's 16 gray steps. The first-round prototype simulated a warm paper (#F1F1EC) and a near-black ink. Those were never device values. The reference screenshots are ADB captures: they keep book covers in color and do not show the panel's real gray levels, so only the UI grays are read from them.

### Primary
- **Ink** (ink, `COLOR_BLACK`): text, icons, interactive outlines (cards, pills, the search field, the popover, buttons), selected fills, the search bar, the toast, the dog-ear, selection handles, the line highlight, and the confirm layer's top rule. Secondary text in the reference is ink at a smaller size, not gray: page header and footer, meta lines, list subtitles and captions are all ink.

### Neutral
- **Paper** (paper, `COLOR_WHITE`): the ground of every screen, panel, card and overlay. It is also the text color on ink fills.
- **Pencil Gray** (ink-2, `COLOR_GRAY_5`): placeholders and the open-book hint (↑ 上滑显示工具栏). Nothing else.
- **Faded Gray** (ink-3, `COLOR_GRAY_9`): disabled labels, such as a font that is not installed.
- **Rule Gray** (rule, `COLOR_GRAY_B`): 1dp structural rules: the toolbar, panel and tab-bar edges, list dividers, the column rules in the progress panel, the rule after the back arrow, cover frames, and disabled outlines and glyphs (the disabled half of the pager).
- **Marker Gray** (mark, `COLOR_LIGHT_GRAY`): the unpassed part of a track, resting font tiles, the origin dot on the progress track, the marker highlight fill, and the brief focus behind the target of a note or bookmark jump.
- **Tint** (tint, `COLOR_GRAY_E`): resting large choice cards (the paragraph cards, the 导入 route tiles).
- **Hit Gray** (hit, `COLOR_GRAY_B`, 0xBB, as measured in `04-contents-and-search/06-search-hit-in-book.png`): the temporary mark behind a search hit in the text.

The black bubble's two grays (bubble-rule and marker-on-ink) are retired with the bubble.

### Cover grays
Generated typographic covers draw from three extra fills: **Cover Stock** (cover-stock, `COLOR_GRAY_D`), the light card ground for the frame and stripe covers; **Cover Tint** (cover-tint, `COLOR_GRAY_B`), the field behind the oversized glyph on split covers; and **Cover Gray** (cover-gray, `COLOR_DARK_GRAY`), the mid-tone block cover. Ink and paper complete the set. These grays appear only on covers.

### Named Rules
**The Monochrome Rule.** Color never carries meaning. Every state reads in black, white and gray, because every target panel is monochrome.

**The Job-Only Gray Rule.** A gray must do a named job (rule, track, resting tile, temporary mark, disabled). Never introduce a gray for mood or depth, and never gray secondary text that the reference sets in ink.

**The Wash Rule.** The only scrim is the wash behind a confirm layer, the 更多 list or the thought editor. Everything behind it is redrawn lighter, so ink lands near `COLOR_GRAY_D` (`Palette.wash`), and it takes no touches. In night mode the page is washed towards its black ground. Panels never wash the page: the typesetting preview must stay readable.

## Typography

**UI font:** Noto Sans with Noto Sans CJK SC, both bundled.
**Reading font:** the reader's choice from the font grid (bundled faces, the user's fonts folder and Android system fonts). The 系统字体 tile is the device's system CJK face, or the bundled Noto Sans CJK SC when there is none. No commercial face is bundled.
**Display serif:** Noto Serif CJK SC or Source Han Serif SC when installed. Otherwise Noto Serif, with CJK glyphs falling back to Noto Sans CJK SC.

**Character:** a neutral CJK sans for every control and every list, including excerpts quoted in notes, search results and lookup cards (the reference sets them in sans). The serif belongs to the reading page, generated covers and the two display titles.

### Hierarchy
- **Reading** (400, user-set 15–28dp in steps 15/16/17/18/19/20/22/24/26/28, default 19; line spacing default 125 %): justified body text. Chinese paragraphs get a 2em first-line indent and a 0.45em paragraph gap. English paragraphs get a 1.5em indent, no gap, and automatic hyphenation. The paragraph panel can set the indent and the gap.
  - *KOReader port:* crengine sets line spacing as a percentage of the face's own line height, which is about 1.45em for the CJK faces. The first-round steps 105 / 125 / 145 % measure about 1.55 / 1.8 / 2.1em on the CJK sans. Latin faces have a shorter natural line height (about 1.36em), so they come out slightly tighter. Font sizes are KOReader dp (`Screen:scaleBySize`), the same numbers as above.
  - *KOReader port:* when a CJK book is opened for the first time (once per install) and no CJK serif is installed, the reader says where to put font files and uses 思源黑体 (the bundled Noto Sans CJK SC). As in upstream ReaderFont, only the first face of a .ttc collection is recognized. Books without a usable language tag (txt, `und`, missing) follow the UI language.
- **Reading chapter** (700, 1.5em, 1.35): chapter titles in the flow, left-aligned and balanced.
- **Display** (serif 700, 22dp): the 书架 title. The 我 page sets the reader's name in the same role at about 28dp.
- **Headword** (700, 20dp): the looked-up word on the first lookup card.
- **Headline** (700, 18dp): titles of full-screen pages (笔记, the book title on the contents page), the book title in the notes overview card, chapter group headings in the notes page, and panel titles (字体设置).
- **Figure** (700, 24dp, tabular): the three figures of the progress panel, each followed by a 13dp unit (%, 分钟, 条).
- **Excerpt** (400, 18dp, 1.45): quoted book text on note cards, clamped to 3 lines with an ellipsis; lookup cards use the same role.
- **Title** (700, 16dp): the 导入 and 选择 actions, selection-mode titles, settings and 我 row titles (17dp on 我), and centered page titles (设置). Confirm-layer actions are 15dp in the same weight.
- **Body** (400, 16dp, 1.45): search-history rows and other list rows. Contents rows set their titles in 700, as in the reference, and their page numbers in 400 at 14dp, tabular.
- **Label** (13dp): book titles under covers (700, one line), font-tile names, meta lines, row subtitles, captions under progress figures, the toast, the confirm-layer question (700, 14dp) and popover labels (700, 12dp).
- **Caption** (400, 12dp, tabular figures): labels inside tracks (700).
- **Page header and footer** (Noto Serif 400, tabular figures; CJK falls back to Noto Sans CJK SC): the reference sets them in a serif, smaller than Caption: the header at 10dp, the footer at 11dp. The open-book hint uses the UI sans at 11dp.

Named font tiles use localized family names, with one regional variant per family chosen for the interface language; Mono variants remain in the full font list. The separate 系统字体 shortcut retains the device's system CJK face (or bundled fallback), even when its region differs from the interface language; a user-installed regional variant never becomes the system shortcut. Long names shrink to 12dp (scaled by the interface font-size setting) before ellipsis, without reducing the tile's touch target.

The interface font-size setting (小 / 默认 / 大 / 较大 / 特大 = 0.9 / 1.0 / 1.1 / 1.2 / 1.35) scales every role above except Reading and Reading chapter. It never changes the page or the DPI. Layouts must keep their touch targets when it is at 特大.

### Named Rules
**The Book Voice Rule.** Serif is for the book's own page, generated covers and the two display titles (书架 and the reader's name on 我). Everything else, including quoted excerpts, uses the UI sans. Book text never uses the UI sans unless the reader chose a sans reading face.

**The Tabular Rule.** Every number that updates in place (page counts, percentages, time, battery, progress figures, track values) uses tabular figures, so a partial refresh does not shift its neighbours.

## Layout

The design is one layout scaled by proportion; the Leaf5 reference fixes its proportions.

- **Bottom band.** The shelf, 书源 and 我 tabs and every new full-screen page end in a 58dp band with a 1dp rule-gray top edge. On the tabs it holds the three tab icons at the left and the joined pager at the right. On full-screen pages it holds the back arrow at the left, optional outline pill actions, and the pager at the right. The reading page has no band; its bottom toolbar appears on request.
- **Gutter.** About 22dp on the left and right of the shelf, panels, lists and settings. Card pages (notes, lookup) center a column about 416dp wide. The import page centers one card at most 458dp wide.
- **Shelf.** From the top: a full-width search field (50dp pill) that opens the home search page, then a title row (the 书架 title or the current filter, such as 在读 ▾, at the left; 导入 and 选择 with circled icons at the right), then the cover grid. On the Leaf5 the grid has four columns: covers about 123 × 178dp with a 22dp column gap, then 12dp down to one bold 13dp title line ending in an ellipsis, and about 24dp to the next row. Other panels compute the column count, keeping the cover size and never shrinking a title's touch area.
- **Reading page.** Only the text, a page header and a page footer. The header is a small circled ‹ glyph (12dp) and the chapter title, at the top left in 10dp serif ink, centered in the top margin. The footer has the time at the left and the current page / total pages at the right (87 / 648), 11dp serif ink and tabular, on a line centered 33dp above the bottom. Both header and footer line up with the text's side margins. Side margins come from the margin track; the design default is 28dp. Pages are columns, never scroll.
  - *KOReader port:* KOReader's dp is proportional, not physical: `scaleBySize` is min(w, h) / 600, unless the user overrides the DPI. Every portrait panel is therefore 600dp wide, and font size scales with it, so 6", 7" and 10.3" set the same line length. The first-round rule "+72dp per side above 800dp" would cut a 10.3" line to about 21 characters. The port instead widens each side by max(0, (W − 2·margin − 38·font size) / 2) dp, recomputed whenever the panel changes the size or the margin, when a book opens, and on rotation. This changes nothing in portrait; it only applies in landscape or with a DPI override, where several margins of the track can widen to the same margins. The margin chosen on the track is therefore saved per book (`typeset_margin`, in dp) instead of being read back from the margins; a first-round book's saved step (`typeset_margin_step`, of 18 / 28 / 44dp) is read once as its margin. It is forgotten when the margins are set some other way (the original bottom bar, gestures), and font size changes then leave those margins as they are. The cap is skipped in two-column mode.
  - *KOReader port:* the page header is drawn only when the top margin holds it with at least 4dp above and below, so it never overlaps the text. It is hidden in scroll mode, when crengine's own top status bar is on, and for fixed-layout books. The design defaults are top margin 44dp, font 19, line spacing 125 % and side margin 28dp; they are written once as global defaults when a book opens with the panel, never over the user's own (whether in the reader settings or customized in defaults.lua). A new default footer must leave a footer the user already customized alone: it replaces only a footer still equal to upstream's default or to the first round's (chapter pages, percentage, time, battery). It lines its ends up with the text through the footer's "same as book margins".
- **Pagination over scrolling.** Every list (shelf, files, contents, notes, search, lookup, settings, fonts) fills its region and pages with the joined pager. There is no "n / N" count between the buttons; the pager's disabled half shows the boundary. Overflow is hidden.
- **Overlay stack.** In order: page (with header, footer and the search bar), toolbars, panel, full-screen page, popover and selection handles, wash with a confirm layer or the thought editor, toast. A sheet opened from a full-screen page (书源's long-press, 分类浏览, edit and menu sheets) stacks above that page.
- **Rhythm.** Gaps step 4 / 8 / 12 / 18 / 22; 13 is the gap between cards.

**The Proportion Rule.** One design from 6" to 10.3". Change columns and margins with the panel and keep the component sizes.

## Elevation & Depth

Flat by construction. E-ink cannot render soft shadows, and the system does not fake them. Depth is conveyed by edges, occlusion and the wash only. A panel is a paper band with a 1dp rule-gray top edge drawn over the page. Toolbars are paper bands with a 1dp rule-gray inner edge. Cards and the popover are paper with a 1dp ink outline. A confirm layer is paper with a 2dp ink top rule over a washed background.

**The Edge, Not Shadow Rule.** Separate surfaces with a 1dp rule or an outline. Never use a drop shadow, blur or gradient. The only scrim is the wash (see Colors).

**The No-Motion Rule.** Nothing animates on the product surface. State changes are a repaint of a named region with a named refresh type.

## Shapes

Two families. **Pills** (radius = half the height) are for everything tappable that sits on a line of controls: search fields (50dp, 40dp on the contents page), segmented controls (38dp), outline pill buttons (34dp; the paragraph pill 29dp), tracks (33dp; the progress track 35dp), the joined pager (42dp), toggles and chips (书源 facets only, 30dp). **Soft rectangles** are for containers: font tiles at 8dp (`tile`), paragraph cards at 12dp (`choice`), the popover at 13dp (`popover`), cards at 14dp (`card`), the bottom sheet's top corners at 16dp (`sheet`), and the import card and the search bar's top corners at 19dp (`large`). Square corners: covers, panels, toolbars and the confirm layer. **Circles** are the ± buttons beside tracks (33dp), the type discs on note cards (25dp), the icon rings on 我 rows (37dp), selection handles and the import page's close button (57dp).

Line weights map onto `size.lua`:
- **1dp** (`Size.border.default`): every rule and every outline (cards, pills, the popover, ± buttons, the pager, type discs).
- **1.5dp** (`Size.border.button`): toggles, the line highlight and the knob of a track.
- **2dp** (`Size.border.thick`): the confirm layer's top rule.
- **4–5dp**: the ink frame around a selected cover in selection mode.

`size.lua` radii (default 2, window 7, button 7) cover none of these; they need new entries.

## Components

### Buttons and pills
- **Outline pill:** paper fill, 1dp ink outline, ink label. Used for 返回原进度, the paragraph entry (首行顶格 ›), 开启自动翻页 (full width, 35dp) and the contents page's 书签 (with a bookmark icon, 42dp like the pager beside it, as in the reference).
- **Text action:** 16dp bold ink text with an optional circled line icon, such as 导入, 选择, 全选, 取消, 保存. No outline.
- **Disabled:** outline and glyph go to rule gray, labels to faded gray.
- **Focus:** 2dp ink outline inset 3dp. No hover state on device.

### Chips
Only 书源 uses chips, for its facets: a 30dp pill, 1dp ink outline, 13dp label, 8dp apart; selected is ink fill with paper text. The shelf has no chips: its status filter lives in the title (see Navigation).

### Segmented control
A 38dp pill with a 1dp ink outline. Segments are split by 1dp ink rules and the selected one is ink-filled with paper text. It is the single-choice control inside a page, such as 全部 / 中文 / 西文 (with counts) on the full-screen font page.

### Tracks (typesetting and progress)
A pill track flanked by two 33dp circle buttons (− and +, 1dp ink outline). The track's passed part is ink and the rest is marker gray. On stepped tracks a 1dp paper rule marks each passed step. The knob is a 33dp paper disc with a 1.5dp ink outline, as measured in both references. It shows the real value in 12dp bold (the font size in dp, the weight step), or the row's name (行距, 边距) when the value has no short number. End labels sit inside the track in 12dp bold: paper on ink at the left (小, 细, 紧, 小), ink on gray at the right (大, 粗, 松, 大). Line spacing and margins have more steps than the first round's three. The old 105 / 125 / 145 % and 18 / 28 / 44dp stay on the track, and a value set elsewhere reads back at its own position without being snapped. Each change re-lays the page out with a partial refresh while the panel stays open.

The typesetting tracks sit on 44dp rows, the ± buttons 9dp from the track. − and + go to the next stop below or above, also from a value between two stops; at either end, the button that would go past it turns rule gray. A tap on the track picks the nearest stop. A value past the last stop, set elsewhere, sits at that end with − or + still leading back onto the track. When the knob's label is longer than the disc (other languages), the knob widens to a pill. Every stop is a value KOReader applies as it is, so a knob reads the real setting:
- **字号:** 15, 16, 17, 18, 19, 20, 22, 24, 26, 28dp (the Reading role's steps), about 41dp apart on a portrait panel. The knob shows the size itself, fractions included (19.5). Sizes past them (KOReader takes 12 and up) stay reachable in the original bottom bar.
- **字重:** the engine's seven weights −1, −½, 0, +½, +1, +1½, +3, in the order of the original bottom bar's 字重 row. The knob shows the step, 1 to 7, so 3 is regular (0, Regular 400), 5 is +1 (Medium 500) and 7 is +3 (Bold 700). A fine-tuned weight between two steps shows 字重 instead of a number.
- **行距:** 85 to 165 % in steps of 10.
- **边距:** 10, 14, 18, 23, 28, 36, 44, 56, 70dp.

The progress track is 35dp tall and runs the gutter width without ± buttons. Chapter arrows ‹ and › sit inside its ends; at the first or last chapter the arrow turns rule gray, like any disabled glyph. Dragging moves only the knob and a preview of the target percentage; the jump happens once, on release (`03-progress/07-progress-drag-preview.png`). While held, the knob is ink in a paper ring, and a gray dot marks where the reader is. A drag goes on when the finger leaves the track, and one let go on the page it started from does not jump.

### Cards
- **Card:** paper, 1dp ink outline, 14dp radius, 20dp padding, 13dp apart. Used for the notes overview, note cards, lookup cards and empty states.
  - *KOReader port:* `scaleBySize` rounds up, so 1dp is 3px on the Leaf5, where the reference outlines cards with 2px. The lookup and notes cards use 0.94dp, which is 2px there.
- **Note card:** a 25dp type disc (1dp ink ring) at the left, on the first line, holds the type glyph (an A for a highlight, a bookmark, the 写想法 head for a thought), then up to three lines in the Excerpt role, ending in an ellipsis. The A carries the highlight's own style: a line under it, a marker behind it, a wave, a strikeout, or inverted. A highlight shows its text; a thought shows the thought, then the text it is on in two 14dp ink lines behind a short ink bar; a bookmark shows the text its page starts with. The padding is 18dp above and below (as measured) and 20dp at the sides; there is no date.
- **Font tile:** marker-gray fill, no outline, 8dp radius, about 106 × 41dp, five per row on the Leaf5. Each name is set in its own face. The current font is ink-filled with paper text. The last tile is 查看更多 ›.
- **Paragraph card:** about 275 × 139dp, 12dp radius, a line icon over a 14dp bold label (首行顶格, 首行缩进). Selected is ink fill with paper content; the other is tint. The 段间距 row sits at the foot of the 首行缩进 card: a 13dp label and a smaller toggle (about 34 × 17dp). On, it is ink with a paper knob, or paper with an ink knob on the selected card; off, it is a faded gray outline and knob over the card, as in the reference. The whole 44dp row switches it.

### Inputs / Fields
- **Search field:** a pill with a 1dp ink outline, a search icon and 16dp text; 50dp tall on the shelf and the home search page, 40dp on the contents page. A filled field shows a round clear button at the right. Placeholders are pencil gray; the contents page's 搜索全书内容 is bold ink, as in the reference.
- **Toggle:** about 47 × 23dp. Off is paper with a 1.5dp ink outline and an ink knob at the left; on is ink with a paper knob at the right.
- **Thought editor:** a compact band docked on top of the keyboard over the wash. A back column (← 返回) is split off by a rule; next to it are a thought icon, the input (placeholder 写下这一刻的想法…) and the quoted excerpt behind a short ink bar; 保存 sits at the right. There is no privacy pill.
- **Labelled field** (forms in sheets, such as 添加书源): a 13dp label column beside a 40dp pill input with a 1dp ink outline. Rows are 52dp minimum. The label column is 92dp, because labels such as "Client Secret" must fit on one line. A form commits with one solid button, disabled until its required fields are filled.

### Navigation
- **Tab bar** (书源 / 书架 / 我): in the bottom band, three 28dp line icons with no labels, about 91dp apart from a 32dp left inset: a compass, a stack of books and a person. The current tab's icon is filled. The joined pager sits at the right.
- **Shelf title row:** the 书架 title is a menu. Tapping it lists 全部 / 在读 / 未读 / 读完 / 搁置, each with its count, in a selection-popover card pointing at the title, the current filter framed. The title then reads the current filter with a ▾ (在读 ▾); 全部 reads plain 书架. The filter is kept until changed. Sorting lives in 设置 → 书架, default 最近阅读.
- **Selection mode:** a long press on a cover enters it with that book selected; 选择 enters it with none. While it is on, a tap on a cover only toggles it. The title row becomes 全选 (or 取消全选, covering the whole shelf, not just the page) at the left, 已选择 N 本书籍 in the middle and 取消 at the right, all 16dp bold. Each cover gets a 25dp ring at its lower right; a selected cover gets a 4–5dp ink frame and an ink check in the ring. The bottom band swaps the tab icons for the two local actions, 移出书架 and 标记为: line icons without labels in the tabs' cells, gray (the reference's 50 % ink) until a book is selected. 全选 takes every book shown, on every page: the current filter. Each action asks in a confirm layer: 移出书架 (是否将《…》移出书架？, or the count for several books, and that the files stay) and 标记为 (读完, 在读, 搁置). Cancel keeps the selection; an action ends selection mode with a toast. 文件's long-press sheet takes the same paths for its status rows and 移出书架. While selecting, the search field takes no taps and Back leaves selection mode. Entering, leaving and 全选 repaint from the title row down with `ui`; selecting one cover repaints only that cover with its frame, the title row and, when it changes, the band.
- **Nav bar** (subpages merged before this round, such as 书源 and the 我 subpages): 52dp with a 1dp ink rule at the bottom, a 52dp back column at the left and a centered 16dp bold title. Those pages keep it until their own tickets move them to the full-screen page form below; new pages do not use it.
- **Full-screen page:** a headline at the top left with an optional text action at the right (↓去底部, 仅显示书签 / 显示全部, 取消). On the contents page ↓去底部 (14dp, as in the reference) becomes ↑去顶部 on the last page, and there is none with a single page. Content follows, then the bottom band: a 28dp back arrow at the left, optional outline pills, and the joined pager.
- **Joined pager:** a 133 × 42dp pill split in two by a 1dp rule: ︿ (previous page) at the left, ﹀ (next page) at the right. An enabled half has an ink outline and glyph; a disabled half has rule-gray ones. These arrows page the list only and never turn book pages.
- **List row:** at least 53dp, with a 1dp rule-gray divider. Contents rows put a 16dp title at the left (indented about 15dp per level, with a collapse chevron before a group; contents without groups keep no chevron column) and the page number at the right. As in the reference, only a top-level entry with entries under it is a group; the groups a reader collapses stay collapsed for that book, but the page shows the current chapter even inside one. The reference has no sample of the current chapter, so it takes the mark of a current item (the font tiles'): its page number is paper on an ink pill, which ends where the other page numbers and the dividers do. Settings and 我 rows are about 92dp: a bold title over a 13dp subtitle, and a toggle or a chevron at the right; 我 rows lead with a 37dp circled icon.

### Reader toolbars
A swipe up, or a tap in the middle, brings two paper bands; while they show, a tap on the page closes them without turning the page. The **top bar** (about 50dp) puts line icons at the right, about 76dp apart, in this order: 书签, 书架状态, 更多. Future 繁简 and 手写 entries go to the left of 书签; nothing holds their place now. The bookmark icon shows whether this page has a bookmark; the 书架状态 icon carries a check while the book is on the shelf. Bookmark actions show a plus or minus; tapping closes the bars and shows 已添加书签 / 已移除书签. The page marker is a solid ink ribbon, nominally 17dp wide and 42dp tall, inset 25dp from the right (mirrored for RTL). It retains ReaderDogear’s margin-based sizing, shrinking in narrow margins, and follows the enabled page header; in scroll mode it starts at the top. Tapping a checked shelf icon closes the bars and asks in the confirm layer; Cancel or Back keeps the book. Removal persists through reading, closing and reopening; an explicit tap on the unchecked icon restores it, keeping the bars open and refreshing only that icon with `fast`. Missing-file records are pruned only when their recorded storage volume is available; unavailable or unknown legacy volumes keep their hidden state. Toolbar membership uses real-path ancestry under the home folder, excluding hidden names, sidecars and KOReader’s own subfolders, without scanning directories. Files outside that boundary stay outside the shelf: the unchecked action explains the home-folder rule and shows its path, without moving or copying the file. 更多 opens the 更多 list as a panel between the page and the bottom bar, the page between the bars washed (see Confirm layer). The **bottom bar** (58dp) has a back arrow at the left, a 1dp rule-gray vertical rule about 25dp tall, then four icons with no labels sharing the rest evenly: 目录, 笔记, 进度, 字体. There is no fifth slot for 听, not even a blank one. The icon of the open panel is drawn filled. Each bar has a 1dp rule-gray inner edge, and both appear and hide with a `ui` refresh limited to their own rects.

**Open-book hint:** each time a book opens (not when a setting reloads it, nor while the footer is hidden, since the text may then reach that line), ↑ 上滑显示工具栏 sits centered on the footer line (3dp above its middle, as in the reference) in 11dp pencil gray, on a paper ground of its own. It stays through page turns until the toolbars first show, or about a minute has passed; then it goes (a `fast` refresh of its rect, or none under the bottom bar) and turning pages does not bring it back.

**Swipe up:** anywhere on the page; in scroll mode only from the bottom edge (the original bottom menu's zone), since swipes scroll there. The gestures plugin's edge and corner gestures keep priority, links and highlights keep their taps, and the original menu's "Activate menu" without swipes turns it off. Brightness has no entry in the bars: 亮度与色温, the first row of the 更多 list, opens its panel in the list's place.

### Panels
The 排版面板 and the 进度面板 are paper bands between the page and the bottom bar, with a 1dp rule-gray top edge and square corners. There is no title bar and no close button. The bottom bar always stays. The top bar stays over the 进度面板 (and the brightness and 更多 panels) and hides over the 排版面板, as the references show. Back leaves one layer at a time, starting with the panel, and another bottom icon switches to its panel in place. The page above stays readable and live.

- **排版面板:** a title row (字体设置 in headline at the left; at the right an outline pill naming the current paragraph mode, 首行顶格 › or 首行缩进 ›, or 段落 › while the book's own styles set the first lines), then four track rows about 44dp apart: 字号, 字重, 行距, 边距. Below them, 当前选择 · font name (16dp bold), then the font grid in three rows. 查看更多 › opens the full-screen font page.
- **Paragraph panel:** opened from the pill. The top bar stays hidden and the bottom bar shows only the back arrow. The panel holds the two paragraph cards, then a 更多排版设置 › row to the other layout options (render mode, embedded fonts and styles, hyphenation, style tweaks, the original bottom bar), whose back arrow returns here. The cards and the toggle set KOReader's paragraph style tweaks for this book only, over any global default: 首行顶格 is "No indentation on first paragraph line", 首行缩进 "Indentation of 2em on first paragraph line" (two characters, as in the reference; KOReader's 1.2em indent reads as 首行缩进 too), 段间距 "Spacing between paragraphs". A card shows selected only when the tweaks make the mode clear. Neither card is selected and the pill reads 段落 in three cases: the book's own styles set the first lines, the tweaks set a mix (such as only the first paragraph of a block indented), or the book's own style tweak sets an indent, which would override the panel. The toggle reads off too while that style tweak sets margins. The toggle works apart from the mode, because no reference shows the two linked. While style tweaks are off for the book, a tap only brings a toast that says so.
- **进度面板:** three columns split by 1dp rule-gray vertical rules: the position (figure and %) over 约 N 小时后读完, the reading time over 阅读时长, and the note count over 笔记. The estimate line is left out when there are no statistics. Tapping the note count opens the notes page. Below are the progress track and 开启自动翻页.
- **返回原进度** (`15-supplement/14-progress-after-drag-jump.png`): after the first jump from the progress panel (a drag, a tap on the track or a chapter arrow), an outline pill ‹ 返回原进度 (29dp tall like the paragraph pill, 13dp label, its width following the label, 26dp above the panel's edge as measured) sits centered just above the panel, and a gray dot marks the origin on the track: marker gray over the passed ink part, and outlined in 1dp ink over the gray part so it stays visible. The dot has no tap of its own: a tap there is a tap on the track. Later jumps keep the 原进度. Tapping the pill returns to its text (the anchor, so a reflow in between does not matter) and closes the panel and the toolbars. The 原进度 also lapses when the toolbars close; switching panels keeps it.
- **加载中…** (`03-progress/08-progress-jump-loading.png`): only a jump that has to wait for the book's layout (a reflowable book still laid out partially after a typesetting change) first covers the page between the bars with 加载中… (13dp bold, centered on the screen as in the reference), the knob resting where it was let go; the page takes its place once laid out.
- **Auto page turn** (`03-progress/02-auto-page-turn.png`, `03-auto-page-turn-settings.png`): 开启自动翻页 starts it. While it runs, an outline pill with a sliders icon and 自动翻页设置 (13dp) sits at the page's bottom left. The pill opens the settings panel: a ∨ at the left that only folds the panel away, 自动阅读 centered, and a 划线导读 toggle at the right (reflowable books only). Below is a speed scale from 慢 to 快 with the five speeds 1.0 / 1.5 / 2.0 / 3.0 / 4.0 (60 / 40 / 30 / 20 / 15 s per page), the current one circled in ink. Last is a full-width outline pill 关闭自动翻页, the only control that stops it. The 划线导读 line is a short ink rule under the current line that steps down line by line, splitting the page interval evenly.

### Bottom sheet
Kept only where it already serves: 书源's long-press sheet, 分类浏览, and the edit and menu sheets of 书源. It is a paper plane with a 1dp ink border and 16dp top corners, bleeding 1dp past the screen edges, with 22dp side padding. Its 54dp header holds a 16dp bold title and a close icon button. Rows are 52dp minimum. A sheet that only navigates (分类浏览) may lay out its rows in two columns with a 22dp gap; the current item is bold with a check mark instead of a chevron. New panels and confirmations do not use this sheet (see Panels and Confirm layer).

### Confirm layer
A full-width paper layer rising from the bottom with square corners and a 2dp ink top rule, over the wash. It has a centered question row (about 53dp, 14dp bold, such as 确认删除该笔记吗？ or 是否将《…》移出书架？), then one row per action (about 58dp, 15dp bold, centered; two-character labels letter-spaced: 删 除, 移 出), then 取 消 last. Rows are split by 1dp rule-gray dividers (`Palette.confirm_rule`, `COLOR_GRAY_B`; `Palette.rule` is still `COLOR_GRAY_D` until the other screens move to this rule gray). Cancel changes nothing, and no touch passes through the wash to the page. The 更多 list uses the same form without the question row: 亮度与色温, 书籍详情, 导出笔记, 点击区域, 阅读统计, 设置, 全部设置（原版）, then 取 消 (设置 added by the owner in review of #41). The reference has no 更多 list; this is the closest form it does show. As a panel (DECISIONS C04), it sits right above the bottom bar with both bars showing, and the wash covers only the page between them, which takes no touches: a tap there closes the list and the bars without turning the page. 取 消, Back and 更多 itself close only the list. 亮度与色温 opens the brightness panel in its place; every other row closes the list and the bars, then opens 书籍详情 (KOReader's book status page: cover, progress, the reader's own rating and review, statistics and book status, shown and closed with `ui`), note export (or the original menu's tools tab while no export format is chosen), the tap zone overlay, the statistics plugin's reading progress, 设置 (the settings page, whose rows that act on the open book work here, unlike from 我 → 设置) or the original menu. Closing what it opened comes back to the page. 导出笔记 is faded (faded-gray label, no action) while the book has no notes; a row whose plugin is off (exporter, statistics) is left out.

### Selection popover (formerly the selection bubble)
A paper popover with a 1dp ink outline, 13dp radius and an arrow about 8dp deep (the outline runs around it) pointing at the middle of the selection's first line, or of its last line when the popover is below. Its cells are about 62dp wide: a 21dp line icon (drawn in a 28dp box) over a 12dp bold label. The order is 划线, then 查询 (for CJK text) or 翻译 (for other text, such as English), 写想法, 复制. On an existing highlight, tapped or long-pressed, the first cell becomes 删除划线 in the same place; after a long-press, 查询/翻译 is for the word pressed. It sits above the selection when there is room, also at the page foot, otherwise below with the arrow flipped, and it stays 16dp from the screen edges, a little outside the gutter, as in the reference. It is pure black and white, so it shows and closes with `fast` on its own rect. There is no second row of styles (see Highlights).

**Selection:** a temporary selection is a 1dp ink underline under the selected text, where a line highlight would be (`07-selection-and-lookup/01-english-word-selected.png`, `15-supplement/33-long-press-release-word-handles.png`), with an ink drop handle (about 25dp) hanging under each end: a disc whose top corner toward the text is square, that corner at the end of the underline and level with the glyphs' bottom, 4dp above the line. It is not an ink fill and not the engine's gray, in reflowable and fixed-layout books alike. The handles hang at the selection's start and end in the order of the text: on a right-to-left line (Hebrew, Arabic) the start is at the right, its handle hanging to the right with the shape mirrored. Fixed-layout pages give no reliable direction, so right-to-left text there gets the underline without handles. A handle is grabbed in a 44dp touch target around it, by a drag or a long-press. It moves its end across lines, and across pages from the page corners as a long-press drag does; the end it moves stays a little above the finger, at the distance it was grabbed from, and the two ends swap when one passes the other. The popover hides while a handle moves. With no explicit selection-action preference, expanding by continuous long-press drag or by dragging a handle saves one highlight on release and shows 删除划线 immediately; moves do not save. A word long-pressed without changing its range stays a temporary selection. Long-pressing a word inside a saved highlight and dragging beyond it saves a separate, potentially overlapping highlight on release; the original highlight is unchanged, as upstream. Explicit legacy selection actions and single-word preferences keep their original behavior. A tap on a handle keeps the selection. Below the selection (at the top of the page) the popover sits under the handles; at the page foot it goes above and the handles stay on the screen.

### Highlights
Three styles, all monochrome. **Line** is the default for new highlights: a pure ink underline 2dp thick, 3dp under the glyphs of the highlighted words on that line (in reflowable books; in fixed-layout ones, at the bottom of the text box). **Marker** (marker-gray fill) and **wave** (1.3dp wavy ink underline, its top where a line would be) stay for existing highlights. The default style is chosen in 设置 → 阅读 → 划线样式, for new highlights only. The new UI does not restyle one existing highlight: existing highlights keep showing in the style they were made with, markers and waves included (ADR-0006). A thought adds a small ink thought mark after the text's last character. A thought written straight on a selection, with no highlight, draws only that mark.

**Search hit:** hit-gray fill behind the matched word while the search bar is up, whatever is selected or highlighted meanwhile. **Jump focus:** after a jump from the notes page to a highlight or a thought, a marker-gray fill behind the target passage for about 1.5 s, which then leaves with a `ui` repaint of its lines (a bookmark's page gets none). Neither is saved, and both are cleared without touching real highlights.

### Search bar
After a jump to a search hit, an ink band (58dp, 19dp top corners) docks at the bottom: a search icon and the keyword in 15dp bold paper at the left, × at the right. The bar belongs to the page, so the toolbar covers it: the hit opens with the toolbar up (`04-contents-and-search/06-search-hit-in-book.png`) and the bar shows once the toolbar goes (`07-search-return-bar.png`). It stays while the reader reads on, and takes only its own taps and holds; the rest of the page turns as usual. A tap on the bar, except on ×, leads back to the results, at the results page the reader left; × closes the search and clears the hit mark, and nothing else.

### Typographic cover
Generated when a book has no cover. Titles use the display serif and authors use the UI sans. Variants: **frame** (double-ruled border with a vertical CJK title), **band** (ink field, paper title, rule, author), **block** (cover-gray field, sans title), **split** (cover-tint top 60% with an oversized paper glyph) and **stripe** (2dp ink stripes behind a ruled cover-stock label). On Latin titles the title size is capped by the longest word, so no word ever breaks or clips.
- **Frame:** every cover, real or generated, has square corners and a 1dp rule-gray frame, about 2:3 on the Leaf5.
- **With a cover image:** a real cover (from the book, or an OPDS thumbnail) fills the same frame, cropped to fill and quantized to 16 grays. For remote books the typographic cover stands in until the image arrives, and a page of images lands in one `ui` repaint of the grid (at most 3 s after the page; later images only go to the cache).
- **读完 badge:** a finished book carries a paper corner tag at the cover's top right, about 31 × 17dp with a 1dp rule-gray frame and 12dp ink 读完 (the reference's glyphs are smaller than the Label role).
- **Download band (书源 only):** while a remote book downloads, a 24dp paper band with a 1dp ink top rule sits at the cover's foot, holding a 4dp ink-on-rule progress bar; the caption under the cover reads 下载中 n%. The cover itself is never tinted. Each progress tick repaints only the band and caption with `fast` (both are pure black and white); the band appearing or leaving over a gray cover is a `ui` repaint of the tile.
- **Downloaded mark (书源 only):** a remote book already on the device carries a 13dp check before the first line of its title; the caption under the title reads 读到 x% once the book is started, otherwise the author. A finished download only repaints its tile (`ui`); it never opens the book, so several downloads can run side by side (ADR-0005). Tapping a marked tile opens the book. Books on the shelf never carry this check: everything on the shelf is local.

### Toast
An ink rounded rectangle (8dp radius, about 47dp tall, 248dp wide for a short text) with 13dp paper text, centered with its bottom about 90dp above the screen's, such as 复制成功 after a copy. It goes away by itself after about 2 s. It shows and leaves with `fast` and must be gone before the next popover appears; over gray covers (the shelf) it leaves with `ui`, which repaints their grays.

### Loading, empty and error states
They sit in the region they replace (a grid, a list), never in a dialog. In order: a 16dp bold ink line, a 13dp ink reason, an optional 12dp tabular line with the technical detail (HTTP 401 · host), then at most one outline pill for the next step (重试, 编辑书源). Loading is the reason line alone (正在连接家里的 NAS…). On card pages the empty state is a card: the notes page keeps its overview card and adds a card that reads 你可以在这里记录本书的想法、划线和书签, with the pager disabled.

### Other pages
These follow their reference screenshots directly, using the parts above:
- **Import** (`15-supplement/02-import-instructions.png`): one centered card (paper, 1dp ink outline, about 19dp radius, 20dp padding, at most 458dp wide) with a section per route: 浏览设备文件, 从书源下载 (only with the OPDS plugin) and 从电脑传书 (USB, plus calibre's wireless connection with its plugin) with the real home folder path. Each section is a 20dp bold headline, a 16dp ink line, and a 56dp tint tile in place of the reference's illustration: a line icon, the route (文件, 书源, Calibre 无线连接) and a chevron. A 57dp circled × sits centered 44dp from the bottom, the card centered in the space above it (at least 34dp clear of the ×); when the card is too tall for that (landscape), the × sits beside it. 书源 opens over the page and returns to it; 文件 returns to it with its back arrow. The calibre tile only starts the wireless connection, which reports its own progress; connecting and disconnecting otherwise stay in 我 → 同步与传书.
- **Files** (文件): the folder list in the content area of the home, opened from 导入, from 我 (whose row names the folder it opens on), or by anything that shows a folder. The bottom band swaps the tab icons for the back arrow, which returns to where 文件 was opened from; Back does the same at the home folder. The band's joined pager turns its pages; it has no pager of its own.
- **Home search** (`15-supplement/08-home-search-query.png`, `09-home-search-results.png`): the search field, then 搜索历史 with an underlined 清空 at the right and history rows. Results are titled 在书架中搜索：xx, with a small cover, 13dp bold title and 11dp author per row (about 26px/22px visible glyphs on Leaf5 at the default UI size). Search covers the entire local shelf, independent of its status filter. History keeps the latest 20 queries. History and results paginate; 清空 asks for confirmation and only clears home search history. The back arrow returns to the shelf with its filter and page kept; the bar sits above the keyboard while typing. There are no recommendation chips or bookstore results.
- **Contents** (`04-contents-and-search/01-contents.png`): book title and ↓去底部, the 搜索全书内容 field, collapsible rows, and 书签 beside the pager.
- **Search** (`04-contents-and-search/04-search-input.png`, `05-search-results.png`, `08-search-no-results.png`): opened from the contents page's field, over that page. The book title, then the field in the same place with 取消 at its right (back to the contents page), and the keyboard. Hits are grouped under chapter headings (Title role); each hit is an excerpt of at most two Body lines with the matched text paper on ink, and a page that goes on with a chapter repeats its heading. Searching shows the reason line alone; when nothing matches, 没有找到相关内容 sits in the list's place and the query stays editable. 书签 and the pager as on the contents page; the back arrow returns to the book.
- **Notes** (`06-notes/01-notes-list.png`, `02-notes-next-page.png`, `05-bookmarks/04-bookmark-in-notes.png`): 笔记 at the left of the title band, over a centered 416dp column: the overview card (book title, → 已读到 x% · 共 N 条笔记, ↗ 时长 N 分钟 when there are statistics, a 64 × 91dp cover at the right) on the first page only, then cards grouped under chapter headings (Headline). N counts every note, bookmarks included, whatever is listed. A page past the first starts under a full-width 1dp rule-gray rule, as the reference's scrolled list does; a heading never ends a page. 仅显示书签 sits at the right of the title band only while the book has bookmarks, as in the reference: one label, its bookmark icon filled while only the bookmarks are listed (the contents page's 书签 opens the page that way); the last bookmark going takes it away. The page reopens on the page left.
- **Lookup** (`07-selection-and-lookup/19-chinese-lookup-settled.png`, `22-english-translation-result.png`): a
  stack of cards: the headword, one card per dictionary named on the card, the 百科释义 card with ›, a centered
  加入生词本 card, and an 在本书中搜索 › row card. Words go to the local dictionaries first. A non-CJK phrase that no
  dictionary has gets an 在线翻译 card marked 需要联网 instead; a word that none has gets a card saying why (not in
  the local dictionaries, none installed), with an 在线翻译 pill for non-CJK text. Chinese never goes to the
  translator. 查询中… sits under the headword while a slow lookup runs (`18-chinese-lookup-result.png`), and in
  the translation card while it waits. A dictionary card too long for the page continues on the next one under
  its name, and a sense taller than a page continues from its next line; nothing is cut (past 100 senses, the
  card says the popup has the rest). A tap on a dictionary card opens its full entry in KOReader's original
  popup over the cards, and closing the popup comes back to them. The 百科释义 card loads its summary on demand;
  its › fetches the exact article in the summary's language and opens its full text on a page with a centered
  title, 46dp side margins and the common bottom back/pager bar. Back restores the query cards and selection.
  Offline, failed and missing requests keep their context and offer Wi-Fi or retry. The article uses the
  existing Wikipedia text and image backend, with the reader's image preference and lazy thumbnail loading,
  without a WebView; original Wikipedia tools remain in the original menus. Short unknown words can also go
  into 生词本 with their book and context, regardless of the vocabulary builder's context setting.
  在本书中搜索 opens the search page with the selected text, preserving inflections even if the dictionary found
  a lemma.
- **我** (`13-reading-preferences/01-profile-entry.png`): the name (display), 累计阅读 X 小时 Y 分钟 with figure-sized numbers, 本周阅读 … | 连续 N 天, then rows.
- **Settings** (`13-reading-preferences/02-settings.png`): a centered title, then toggle and chevron rows.
- **Interface font size** (`13-reading-preferences/03-interface-font-size.png`): 字体大小 under 设置 → 阅读, showing the current size. The page has the heading 点击滑块设置界面字体大小 (title) over a label-sized note that the book's text is sized in the reader. Above the bottom band sits a track between the − and + circles, with the five sizes as steps (no step marks), 小 and 大 inside its ends and the current size's name (12dp bold) above the knob. It is the typesetting track (see Tracks) without step marks, its stops running to the track's ends, so the knob covers 小 or 大 at the first or last size. A tap on the track or on − / + applies the size at once and repaints the page above the band with `ui`. − and + are gray at the ends.
- **Thought card and detail** (`07-selection-and-lookup/08-private-thought-detail.png`, `09-private-thought-full-detail.png`): tapping a thought mark shows a card with the quote and the thought; the card opens a full-screen detail with the quote (which leads back to the text), edit and delete. No avatar, likes or comments; a static 仅自己可见 is allowed.
- **Book end** (`15-supplement/21-finish-page-mark-button.png`, `12-book-ending/04-book-end.png`): 全书完 with 标记读完 or the finished state and local statistics; the toolbars still open here.
- **Image preview** (`09-images/02-image-preview.png`): the image centered on an ink ground; a double tap toggles fit and zoom.
- **Footnote popup:** there is no reference sample; KOReader's popup keeps its flow and takes a card's paper, 1dp ink outline and radius.

### Refresh mapping
Each interaction declares one KOReader refresh type and the smallest rect set it repaints:
- **partial:** page turns, reflow after a type change (the panel stays open), and jumps to a chapter, bookmark, note, search hit or the 原进度.
- **ui:** toolbars and panels (their own rects), the progress knob's drag preview (the track and the position figure), the 加载中… cover and where the 返回原进度 pill was, the 段间距 toggle on its gray card, switching panels, full-screen pages opening, paging and filtering, tab switches, the confirm layer and its wash (and the 更多 list's, from under the top bar to the bottom bar), and the search bar's × (the bar and the hit mark).
- **fast:** the selection popover, selection handles and underline (the lines and handles of the old and new selection as it changes; `ui` for a long-press's first word, where a marker highlight, an image or a fixed-layout page is under them, and over the whole page once a selection across pages scrolled it), the bookmark dog-ear, toggles, the open-book hint, the toast, and the auto page-turn guide line (only its own strip).
- **full:** opening a book, returning to the shelf and switching night mode. Page turns keep KOReader's own full-refresh cadence. No other new UI action asks for `full`.

A static screenshot cannot show which refresh ran; check refreshes on the device by watching.

## Local substitutes

Where the reference depends on WeChat accounts, the cloud, the community or the bookstore, the fork shows a local substitute or nothing. It never draws a fake button. These substitutes are deliberate; do not "fix" them back toward the reference. The full rulings are in `DECISIONS.md`.

| Reference | This fork |
| --- | --- |
| Tabs 发现 / 书架 / 我 | 书源 / 书架 / 我; 书源 uses a compass icon. Files open from 导入 and from 我. |
| 导入 explains the phone app and r.qq.com | 浏览设备文件, 从书源下载, and 从电脑传书 (Calibre wireless, or USB into the home folder, with its real path) |
| Selection mode: 下载, 移出书架, 私密 | 移出书架 (hides the book, never deletes the file, always confirmed) and 标记为 (读完 / 在读 / 搁置) |
| Home search: recommendation chips and a bookstore section | Local titles and authors only, under 在书架中搜索：xx |
| Top bar: 繁简, 书签, 手写, 书架, 下载状态 | 书签, 书架状态, 更多. 更多 takes the place of 下载状态. 繁简 and 手写 are left out this round. |
| Bottom bar ends with 听 | No 听, and no empty slot |
| Popover action 听当前 | None |
| Thought editor: 发表 and a 私密 pill | 保存 and no privacy control; a thought's detail may show a static 仅自己可见 |
| Lookup: Sogou encyclopedia | 百科释义 (Wikipedia summary); › opens the full article |
| Lookup: 全书繁转简 card | 加入生词本 (with its source) |
| Lookup: 去书城搜索 row | 在本书中搜索 |
| One highlight style | Line by default; marker and wave stay for old highlights and in 设置 → 阅读 → 划线样式 (ADR-0006) |
| 我: account, 微信文章, 微信读书阅读器 rows | 全部书笔记, 生词本, 文件, 同步与传书, 设置, 版本更新 (KOReader OTA with the current version) |
| Book end: community rating and recommendations | Local statistics; 读完的第 N 本 counts the books marked 读完 locally, with no year limit |
| Community bubbles, popular highlights, other readers' thoughts | None |

Listening, handwriting, simplified/traditional conversion and image highlights are left to the owner this round. They get no entry and no placeholder.

KOReader capabilities that WeChat Read lacks stay reachable from a secondary entry: brightness and warmth, book details with the reader's own rating and review, note export, tap zones, statistics, the settings and the 原版入口 under 更多; 刷新与残影 under 设置 → 屏幕; advanced typesetting, search options and the original settings through their existing paths.

## Do's and Don'ts

### Do:
- **Do** separate structure with 1dp rule-gray rules and outline touchable units in 1dp ink.
- **Do** show the current choice as an ink fill with paper text.
- **Do** open typesetting and progress as panels between the page and the bottom bar, with the bottom bar still showing; the top bar stays over progress and hides over typesetting.
- **Do** put contents, notes, search results, lookup and settings on full-screen pages with the back arrow at the bottom left and the joined pager at the bottom right.
- **Do** use icons without labels in the tab bar and the reader toolbars, and labels under icons in the selection popover.
- **Do** confirm destructive or hiding actions with the confirm layer over the wash.
- **Do** keep touch targets at 44dp or more, also at the largest interface font size.
- **Do** use tabular figures for every number that updates in place.
- **Do** name the refresh type and repaint region for every new interaction; only `full` may flash.
- **Do** implement night mode as inversion of the whole screen, not as a second palette.
- **Do** keep other UI languages, fixed-layout books' own controls, physical page keys and the 原版入口 working; the reference only shows Chinese, touch and reflowable books.

### Don't:
- **Don't** use color to carry meaning; the panels are monochrome.
- **Don't** use drop shadows, blur or gradients for depth, or any scrim other than the wash.
- **Don't** animate anything on the product surface.
- **Don't** make lists scroll.
- **Don't** put new adjustments in a rounded sheet with a close button, or hide the bottom bar when a panel opens.
- **Don't** gray secondary text that the reference sets in ink.
- **Don't** set controls or excerpts in the serif, or book text in the UI sans unless the reader chose it.
- **Don't** draw a button for a service the fork does not have, not even disabled.
- **Don't** take sizes or colors from `design/demo/`; it is the first-round prototype.
