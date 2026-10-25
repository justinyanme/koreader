# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

Recorded as `web` because the design language is custom and self-drawn, not Material or HIG. The real runtime is KOReader's LuaJIT widget framework on e-ink devices. Prototypes for this redesign are built as web pages.

## Stack

Design prototypes: single-file static HTML/CSS/JS (user's choice). Production implementation later happens in KOReader's Lua widget framework (`frontend/ui/widget/`), not in web tech.

## Users

Primary user: the owner of this fork, reading on their own e-ink devices — Android-based e-ink readers at 6", 7" and 10.3", plus one Kindle. A tiny Xteink X4 Pro may not be able to run KOReader at all.

The same owner also reads on an iPhone and iPad. These use the same paged, motionless interface, with point-sized controls and a safe-area viewport.

They read Chinese and English books, mostly non-fiction, mostly EPUB. The job is long-form reading with low friction on a slow, grayscale screen.

## Product Purpose

A personal redesign of KOReader's interaction and visual design for e-ink. Keep KOReader's engine and format strength. Make the everyday reading flows fast, calm and deliberate-looking on e-ink.

Success: common actions take fewer taps and fewer screen refreshes than today. Those actions are opening a recent book, turning pages, adjusting type, jumping chapters, highlighting and looking up a word. The UI should look intentional on a grayscale panel rather than like a settings dump.

## Positioning

KOReader is an offline, open-source reader with deep typesetting control (crengine) and fixed-layout handling (MuPDF, k2pdfopt). It runs on both Android e-ink and Kindle, and plugins and user patches can change any part of it. No store or vendor reader offers that combination. The redesign brings a consumer-grade reading UX to that engine without giving up the control.

## Operating Context

- iOS 27 or later, full-screen iPhone and iPad in portrait and landscape; split view and multiple windows are deferred. 1dp ≈ 1pt, independent of display pixel density (T0: iPhone 3px/pt, iPad 2px/pt). The safe area holds controls and reading content; the background fills the display. The system status bar is hidden; app chrome and the reading footer show time and battery.

- E-ink panels: 16-level grayscale, slow refresh (partial, full, fast/A2 modes), ghosting after many partial refreshes, no usable animation, touch latency.
- Device range 6"–10.3", roughly 212–300 DPI. Portrait is primary.
- Most devices are Android e-ink, where refresh is driven through vendor e-ink hooks in the Android launcher. The Kindle uses the Linux framebuffer path.
- Long reading sessions with frequent pick-up and put-down. Chinese and English text, often in the same library.
- UI language: Chinese (inferred from the user; not explicitly confirmed).

## Capabilities and Constraints

- iOS keeps the e-ink UI grammar and grayscale chrome. Book illustrations, PDF pages and original cover images retain engine color. Night mode inverts the whole screen and does not follow system dark mode.
- Device capabilities govern available features: iOS has system brightness and no e-ink refresh/ghosting controls, warmth, OTA update or process-fork support. System pickers, keyboard and sharing are native integration paths. The initial iOS scope is recorded in `doc/ios/decisions.md` Q20–Q22.

- The full KOReader feature set exists today: library/file browser, cover browser, history, collections, reflowable and fixed-layout reading, typesetting controls, TOC/bookmarks/book map, highlights and notes with export, dictionary/Wikipedia lookup, vocabulary builder, statistics, gestures, sync (KOSync, calibre, OPDS, cloud), plugins.
- For personal use, low-frequency features may be demoted or removed from the primary UI.
- Everything designed must be implementable in KOReader's Lua widget framework: drawn on a Blitbuffer, grayscale-first, no animation, explicit refresh regions, bundled fonts.
- Design and prototype first. Make no KOReader code changes until the design is agreed.
- Undecided: which specific features get cut.

## Brand Commitments

- Name: KOReader (personal fork at `justinyanme/koreader`).
- WeChat Read's (微信读书) e-ink edition is the pinned look and interaction model. The user's words: "跟微信读书一样就行，不一样那就是有问题". Deviating from it counts as a defect unless a KOReader capability has no WeChat Read equivalent.
- E-ink remains the primary target. iOS adds color displays; color never carries meaning in interface chrome.

## Evidence on Hand

- Feature inventory: `frontend/apps/`, `plugins/`, menu structure in `frontend/ui/elements/*_menu_order.lua`.
- Existing icon set: `resources/icons/mdlight/` (105 SVGs). Bundled fonts: `resources/fonts/`.
- No user research, device screenshots or usage data exist. Do not fabricate any.

## Product Principles

1. The page is the product: reading content owns the screen, and chrome appears only on demand.
2. Fewer taps, fewer refreshes: every interaction is judged by its tap count and the screen area it repaints.
3. Common in front, power behind: KOReader's depth stays reachable but never sits in the path of daily reading.
4. Designed for the panel: rely on black/white contrast and structure, not mid-grays, shadows or motion.
5. One design from narrow iPhone to 10.3" e-ink and iPad: preserve component proportions and change columns or interaction rules when width requires it.

## Accessibility & Inclusion

- iOS uses a 44pt minimum touch target, including invisible extensions around smaller drawn controls. R05 supplies five interface font sizes. Initial native keyboard/picker/share UI follows the system; VoiceOver’s five-flow minimum is a later milestone (Q21), not an implemented capability here.
- At narrow widths, covers keep their reference size in fewer columns; crowded typesetting tracks advance one stop toward a tap rather than requiring precise selection of overlapping stops.

- Large touch targets, because e-ink touch is imprecise and slow to confirm.
- Type size and contrast stay user-adjustable everywhere text is read.
- Physical page-turn buttons and keyboard/D-pad navigation must keep working on devices that have them.
