import ProjectDescription

// Just Reader, the iPhone and iPad port of this KOReader fork. SDL3 owns the window and the scene;
// JustReader/Sources/main.swift boots the Lua VM that koreader-base and the Lua tree run in, all linked
// statically into the executable. Build: doc/ios/build.md. Delivery: doc/ios/delivery.md.
let project = Project(
    name: "JustReader",
    targets: [
        .target(
            name: "JustReader",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "me.justinyan.justreader",
            deploymentTargets: .iOS("27.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Just Reader",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "ITSAppUsesNonExemptEncryption": false,
                "LSApplicationCategoryType": "public.app-category.books",
                "UILaunchScreen": [:],
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false,
                    "UISceneConfigurations": [
                        "UIWindowSceneSessionRoleApplication": [[
                            "UISceneConfigurationName": "Default",
                            // SDL_RunApp installs it as the app delegate too.
                            "UISceneDelegateClassName": "SDLUIKitSceneDelegate",
                        ]],
                    ],
                ],
                // B3 (#91, Q10): Documents shows in Files as On My iPhone › Just Reader and in Finder's
                // file sharing; "Open with" hands the app a copy (frontend/apps/shelf/bookimport.lua).
                "UIFileSharingEnabled": true,
                "LSSupportsOpeningDocumentsInPlace": false,
                "CFBundleDocumentTypes": [[
                    "CFBundleTypeName": "Book",
                    "CFBundleTypeRole": "Viewer",
                    "LSHandlerRank": "Alternate",
                    "LSItemContentTypes": [
                        "org.idpf.epub-container", "com.adobe.pdf", "public.plain-text", "public.html", "public.rtf",
                        "com.microsoft.word.doc", "org.openxmlformats.wordprocessingml.document",
                        "org.oasis-open.opendocument.text", "net.daringfireball.markdown",
                        "me.justinyan.justreader.fb2", "me.justinyan.justreader.fb3", "me.justinyan.justreader.mobi",
                        "me.justinyan.justreader.djvu", "me.justinyan.justreader.cbz", "me.justinyan.justreader.cbr",
                        "me.justinyan.justreader.chm",
                    ],
                ]],
                // Book formats the system has no type for.
                "UTImportedTypeDeclarations": .array([
                    ("fb2", "FictionBook", ["fb2"], ["public.xml"]),
                    ("fb3", "FictionBook 3", ["fb3"], ["public.zip-archive"]),
                    ("mobi", "Mobipocket eBook", ["mobi", "prc", "azw", "pdb"], ["public.data"]),
                    ("djvu", "DjVu Document", ["djvu", "djv"], ["public.data"]),
                    ("cbz", "Comic Book (ZIP)", ["cbz"], ["public.zip-archive"]),
                    ("cbr", "Comic Book (RAR)", ["cbr"], ["public.data"]),
                    ("chm", "Compiled HTML Help", ["chm"], ["public.data"]),
                ].map { id, name, extensions, conforms -> Plist.Value in
                    [
                        "UTTypeIdentifier": .string("me.justinyan.justreader.\(id)"),
                        "UTTypeDescription": .string(name),
                        "UTTypeConformsTo": .array(conforms.map { .string($0) }),
                        "UTTypeTagSpecification": ["public.filename-extension": .array(extensions.map { .string($0) })],
                    ]
                }),
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
            ]),
            buildableFolders: [
                "JustReader/Sources",
                "JustReader/Resources",
            ],
            scripts: [
                // Builds koreader-base and the Lua payload, and writes link.args (make/ios.mk).
                .pre(path: "scripts/xcode-prepare.sh", name: "Build koreader-base and Lua payload",
                     outputPaths: ["$(KO_INSTALL_DIR)/ffi-symbols.exp"], basedOnDependencyAnalysis: false),
                // Copies the payload into the app, then the nm symbol gate (Q27, Q35).
                .post(path: "scripts/xcode-finish.sh", name: "Embed Lua payload and check symbols",
                      basedOnDependencyAnalysis: false),
            ],
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "SWIFT_OBJC_BRIDGING_HEADER": "JustReader/Sources/JustReader-Bridging-Header.h",
                "DEVELOPMENT_TEAM": "V88UWDRASU",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "CODE_SIGN_STYLE": "Manual",
                "CURRENT_PROJECT_VERSION": "1",
                "MARKETING_VERSION": "1.0",
                // koreader-base output for this SDK (base/Makefile.defs names it after the clang triple).
                "KO_MACHINE[sdk=iphonesimulator*]": "arm64-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET)-simulator",
                "KO_MACHINE[sdk=iphoneos*]": "arm64-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET)",
                "KO_ROOT": "$(SRCROOT)/../..",
                "KO_INSTALL_DIR": "$(KO_ROOT)/koreader-ios-$(KO_MACHINE)",
                "KO_STAGING": "$(KO_ROOT)/base/build/$(KO_MACHINE)/staging",
                "HEADER_SEARCH_PATHS": "$(KO_STAGING)/include $(KO_STAGING)/include/luajit-2.1",
                // koreader-base, LuaJIT and SDL3, exporting each ffi-symbols.txt entry (make/ios.mk).
                "OTHER_LDFLAGS": "@$(KO_INSTALL_DIR)/link.args -Wl,-exported_symbols_list,$(KO_INSTALL_DIR)/ffi-symbols.exp",
                "ARCHS": "arm64",
                // Archives strip the executable: keep its exports, the FFI resolves them at run time.
                "STRIP_STYLE": "non-global",
                // One Mach-O: Xcode's debug dylib would move the exports out of the executable.
                "ENABLE_DEBUG_DYLIB": "NO",
                // The script phases run make across the repo, outside any declared inputs.
                "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
            ], configurations: [
                // Debug: Xcode runs and OTA, signed manually with match's development profile;
                // `mise run ios:certs` installs it. The identity is match's development cert
                // 59A4GCYDB5 by SHA-1: "Apple Development" picks the newest cert of that name, an
                // Xcode-made one the profile doesn't carry. Update the hash when match renews the cert.
                .debug(name: "Debug", settings: [
                    "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "E41D0C0A78C37D78569EEF574001FC6894346294",
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": "match Development me.justinyan.justreader",
                ]),
                // Release: TestFlight, signed manually with match's App Store profile. Simulator
                // builds stay ad-hoc signed.
                .release(name: "Release", settings: [
                    "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "Apple Distribution",
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": "match AppStore me.justinyan.justreader",
                ]),
            ])
        ),
    ]
)
