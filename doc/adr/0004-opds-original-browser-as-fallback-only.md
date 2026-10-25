# 书源新界面只覆盖"远程书架"，原版 OPDS 浏览器只做兜底、不改动

OPDS 插件的新界面（书源）只重做界面层，协议层（opdsclient / opdsparser / cookiejar）保持不动。例外是 `opdsclient.lua` 的两处改动：新增 `auth_headers`，只发给同源地址，因为 Service Token 绝不能泄露到其他源（见 #24）；按 decisions.md Q34 授权，它还承载共享的同源判断 helper，供书源初始授权和跳转循环每一跳共用（见 #88）。协议层其余部分都不动。新界面只覆盖三件事：浏览、搜索、下载书源里的书。同步书源到文件夹、PSE 流式阅读、下载队列这三项不进新界面，只能从原版入口里的原版 OPDS 浏览器使用。我们不为原版浏览器改上游的 `opdsbrowser.lua`，这样每月合并上游时不会多出冲突。

## Consequences

新界面为书源加了 Cloudflare Access 的 Service Token（`CF-Access-Client-Id` / `CF-Access-Client-Secret`），用来连接挂在 Cloudflare Tunnel 后面的家用 NAS。原版浏览器不会发送这两个请求头，所以连不上被 Access 保护的书源。另外，在原版浏览器里编辑一个书源时，书源记录会被整个重建（`editCatalogFromInput`），token 字段会丢失。丢失以后，新界面会显示"登录失败 → 编辑书源"，重新填一次即可。这个代价可以接受，不要为它去改上游文件。
