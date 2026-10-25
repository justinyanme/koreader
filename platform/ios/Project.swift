import ProjectDescription

// Just Reader, the iPhone and iPad port of this KOReader fork. D0 (#131) is an empty shell for the
// TestFlight and OTA channels; B1 adds koreader-base and the Lua VM. Delivery: doc/ios/delivery.md.
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
                            "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).SceneDelegate",
                        ]],
                    ],
                ],
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
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "DEVELOPMENT_TEAM": "V88UWDRASU",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "CODE_SIGN_STYLE": "Manual",
                "CURRENT_PROJECT_VERSION": "1",
                "MARKETING_VERSION": "1.0",
            ], configurations: [
                // Debug: Xcode runs and OTA, signed manually with match's development profile;
                // `mise run ios:certs` installs it. The identity is match's development cert
                // 59A4GCYDB5 by SHA-1: "Apple Development" picks the newest cert of that name, an
                // Xcode-made one the profile doesn't carry. Update the hash when match renews the cert.
                .debug(name: "Debug", settings: [
                    "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "E41D0C0A78C37D78569EEF574001FC6894346294",
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": "match Development me.justinyan.justreader",
                ]),
                // Release: TestFlight, signed manually with match's App Store profile.
                .release(name: "Release", settings: [
                    "CODE_SIGN_IDENTITY": "Apple Distribution",
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": "match AppStore me.justinyan.justreader",
                ]),
            ])
        ),
    ]
)
