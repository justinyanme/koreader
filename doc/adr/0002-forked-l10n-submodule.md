# 新界面文案用英文原文，中文翻译放在 fork 的 l10n 子模块里

KOReader 的界面文案统一写成 `_("English")` 形式的英文原文，翻译放在 `l10n` 子模块（koreader-translations 仓库）里。新界面同样遵守这个规则：优先复用已有的英文原文；新增的文案写英文原文，中文翻译加到我们 fork 出来的 l10n 子模块中，而不是在代码里直接写中文。这样做的代价是要多维护一个子模块 fork，并且 merge 上游时要同步它；好处是合并上游代码时不会和写死的中文起冲突，切换语言也照常工作。

## Consequences

fork 是 justinyanme/koreader-translations，`.gitmodules` 指向它的 https 地址；子模块里 `origin` 是 fork，`upstream` 是 koreader/koreader-translations。我们新增的词条放在 `zh_CN/koreader.po` 末尾的 `# eink-redesign` 区块里。上游的 msgmerge 不认识这些词条，同步时可能把它们标成作废（`#~`）或删掉。每月合并上游时按这个顺序做：

1. 在 l10n 里把 `upstream/master` merge 进 fork 的 master。
2. 检查 `# eink-redesign` 区块；如果被删掉或标成作废，重新追加到文件末尾，然后推送到 fork。
3. 在主仓库里提交新的 l10n 指针（gitlink）。`./kodev build` 会把 .po 编译成 .mo。
