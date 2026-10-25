# 发布：TestFlight 与 OTA

Just Reader（`me.justinyan.justreader`，iPhone + iPad）有两条发布通道，都在发布用的 Mac 上从仓库根目录运行。做法照搬 justoodoo 的 `docs/agents/delivery.md`（[Q45](decisions.md)），只做 iOS，没有 Mac 版，也不用 CloudKit、推送。

| 命令 | 作用 |
|---|---|
| `mise run ios:generate` | 用 Tuist 生成 `platform/ios/JustReader.xcworkspace`，不打开 Xcode。生成的工程不入库。 |
| `mise run ios:tf` | 构建 Release `.ipa` 并上传 TestFlight。等 Apple 处理完后提交 Beta App Review，加入 "External" 组，审核通过后测试者收到邀请。"Internal" 组自动拿到每个 build。What to Test 默认是最后一条提交的标题，可以用 `mise run ios:tf 'changelog:<文字>'` 覆盖。Apple 同一时间只审一个 build：上一个还在审时，新 build 只留在 Internal，lane 会提示，等审核结束后在 App Store Connect 里手动加进 External。 |
| `./kodev build ios-device` | 运行 fastlane 的 `build_release` lane：构建并导出与 `ios:tf` 相同的 App Store 签名 `.ipa`，但不上传。和 `ios:tf` 一样需要 `.env`，并且会调用一次只读的 App Store Connect 接口取 build number。见 [build.md](build.md)。 |
| `mise run ios:ota` | 构建开发签名的 Debug `.ipa`，发布到 <https://test.justinyan.app/justreader/>。 |
| `mise run ios:certs` | 只读安装本 App 的全部签名（App Store 和开发）。 |
| `mise run ios:refresh_profiles` | 新建或刷新本 App 的两个 match profile，见下文。 |

**Build number.** 两条通道的 build number 都是最新 TestFlight build 加 1。iOS 不允许用 build number 更小的 OTA 包覆盖已装的 TestFlight 版，所以先 `ios:tf` 再 `ios:ota`。App Store Connect 里还没有 App 记录时，两个命令都会失败。

**版本号.** `MARKETING_VERSION` 写在 `platform/ios/Project.swift`，目前是 1.0。

## 前提

1. **工具链：** 在仓库根运行 `mise trust`（配置会加载 `.env`，mise 要先信任）、`mise install`，再在 `platform/ios/` 里运行 `mise exec -- bundle config set --local path vendor/bundle` 和 `mise exec -- bundle install`。版本固定在根目录的 `mise.toml`：tuist 4.155.3、ruby 4.0、xcbeautify 3.2.1；fastlane 由 `platform/ios/Gemfile.lock` 固定。lane 构建 App 时，Xcode 的预构建脚本会先构建 koreader-base，所以还需要 [build.md](build.md#前提) 里的 Homebrew 构建依赖；第一次构建 base 要十几分钟。
2. **Xcode：** 用 Xcode 27.1。`xcode-select -p` 不指向它时，命令前加 `DEVELOPER_DIR=/Applications/Xcode-27.1.0.app/Contents/Developer`。
3. **环境变量：** 仓库根的 `.env`（已在 `.gitignore`）提供
   - `ASC_KEY_ID`、`ASC_ISSUER_ID`；
   - `ASC_KEY_PATH`，`.p8` 的绝对路径；
   - `MATCH_PASSWORD`。

   值和 justoodoo、Just-ABC 相同，直接链接过来：`ln -s /Users/justinyan/Documents/jproj/justoodoo/.env .env`。可选的 `MATCH_KEYCHAIN_PASSWORD` 默认等于 `MATCH_PASSWORD`；钥匙串建好后不要再改。
4. **SSH：** 发布用的 Mac 要能
   - 非交互地访问 `git@github.com:justinyanme/jtf-mac-certs.git`；
   - 跑通 `ssh -o BatchMode=yes heredev@192.168.31.150 true`。
5. **设备（只有 OTA 需要）：** iPhone 和 iPad 已注册到 Team `V88UWDRASU` 并在开发 profile 里，打开了开发者模式，运行着 Surge（`test.justinyan.app` 只在 mesh 内解析）。

## 签名

- **证书**通过 match 与 justoodoo、Just-ABC 共用，按 ID 固定：
  - Apple Distribution `7MB766938Z`；
  - Apple Development `59A4GCYDB5`，**2026-12-15 到期**。
- **Profile**（App ID 没有额外能力）：
  - `match AppStore me.justinyan.justreader`；
  - `match Development me.justinyan.justreader`（包含所有已注册的 iPhone 和 iPad）。
- **工程签名：** 两种配置都用 match 的 profile 手动签名（`platform/ios/Project.swift`），不自动签名。
  - Debug 用于 Xcode 运行和 OTA，用开发 profile。开发证书按 SHA-1 指定，因为写 "Apple Development" 会挑到最新的同名证书，那是 Xcode 自己建的、profile 里没有。match 续签证书后要更新 `Project.swift` 里的哈希。
  - 第一次在真机上用 Xcode 运行之前，先 `mise run ios:certs`：除了签名钥匙串，它还把开发证书装进登录钥匙串，Xcode 从那里找。
  - Release 用于 TestFlight，用 App Store profile。
- **导出：** 每次导出都显式写明 profile（`skip_profile_detection`）。
- **模拟器构建**不用 match：两种配置的证书和 profile 都只对 `iphoneos` 生效，模拟器包做 ad-hoc 签名。

**App ID 能力变了或新增设备后，刷新 profile：**

```sh
mise run ios:refresh_profiles
```

它先只读检查两张共用证书，再新建或更新本 App 的两个 profile，只往 match 仓库写 `me.justinyan.justreader` 的文件，不新建、不撤销证书。其余 lane 都是只读的。

**签名钥匙串.**
- 签名在独立的 `justreader-signing` 钥匙串里进行。作业期间它解锁并排在用户搜索列表最前面。同样的证书也在其他项目的钥匙串里，从那里签会报 `errSecInternalComponent`。
- 作业开始前记下搜索列表，结束后恢复，成功或失败都恢复。
- 签名作业一次只跑一个。

**rsync.** lane 把 `/usr/bin/rsync` 放在 `PATH` 最前面，因为 Homebrew 的 rsync 会弄坏 Xcode 的 IPA 打包。

## App Store Connect

App 记录要用 owner 的 Apple ID 网页会话创建，API 建不了。TestFlight 配置照抄 Justtoodoo（App ID `6760220075`）：先建 "Internal" 内部组（可访问所有 build）和 "External" 外部组（开公开链接和反馈），测试员、TestFlight 测试信息、Beta 审核联系人都用 `asc` CLI 从 Justtoodoo 读出现有值再写过来（`ASC_PRIVATE_KEY_PATH=$ASC_KEY_PATH`）。

`ITSAppUsesNonExemptEncryption = NO` 写在 Info.plist 里，上传后不用回答出口合规问题。

## 本地运行

```sh
mise run ios:generate
cd platform/ios
xcodebuild -workspace JustReader.xcworkspace -scheme JustReader -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath Build/SimDerivedData build
xcrun simctl install <设备> Build/SimDerivedData/Build/Products/Debug-iphonesimulator/JustReader.app
xcrun simctl launch <设备> me.justinyan.justreader
```

冒烟用 iOS 27.0 运行时上的 iPhone 17 Pro Max 和 iPad Pro 11 英寸（M5）模拟器（[Q42](decisions.md)）。本机的 iOS 27.1 运行时（24A94425）只支持 iPhone Duo 机型。

## 验证一次发布

1. **OTA 安装页：** `curl -I https://test.justinyan.app/justreader/manifest.plist` 返回 200。
2. **TestFlight：** 在 App Store Connect 里，iOS build 先到 `VALID`，Internal 组是 `IN_BETA_TESTING`，External 组是 `WAITING_FOR_BETA_REVIEW`（之后变成 `BETA_APPROVED`）。
3. **钥匙串：** 运行前后的 `security list-keychains -d user` 一致。
4. **真机：** owner 在 iPhone 或 iPad 的 Safari 里打开 OTA 页安装，或者通过 TestFlight App 安装。owner 确认之前，验收不算完成。
