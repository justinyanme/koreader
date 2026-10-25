# iPhone and iPad: koreader-base and the Lua tree inside the Swift/UIKit app in platform/ios/.
# `./kodev build ios` builds the simulator Release, `./kodev build ios-device` the signed device
# Release, and `./kodev run ios` installs and launches it in a simulator.

IOS_DIR = $(PLATFORM_DIR)/ios
IOS_BUNDLE_ID = me.justinyan.justreader
IOS_CONFIGURATION ?= Release
# Simulator name or UDID for `./kodev run ios`.
IOS_SIMULATOR ?= booted
IOS_PAYLOAD = $(INSTALL_DIR)/payload
IOS_DERIVED_DATA = $(abspath $(INSTALL_DIR))/DerivedData

ifeq ($(IOS_PLATFORM), iphonesimulator)
  IOS_APP = $(IOS_DERIVED_DATA)/Build/Products/$(IOS_CONFIGURATION)-$(IOS_PLATFORM)/JustReader.app
else
  IOS_ARCHIVE = $(abspath $(INSTALL_DIR))/JustReader.xcarchive
  IOS_APP = $(IOS_ARCHIVE)/Products/Applications/JustReader.app
endif

# Plugins (Q31): Android's excludes, then the ones running external binaries or shells, and the
# e-ink-only ones. iOS dims and suspends the screen itself.
define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autodim.koplugin
plugins/autofrontlight.koplugin
plugins/autostandby.koplugin
plugins/autosuspend.koplugin
plugins/autowarmth.koplugin
plugins/coverimage.koplugin
plugins/hello.koplugin
plugins/httpinspector.koplugin
plugins/keepalive.koplugin
plugins/systemstat.koplugin
plugins/terminal.koplugin
plugins/timesync.koplugin
tools
endef

# The app links koreader-base statically (libs/) and can't run executables (sdcv).
define UPDATE_PATH_EXCLUDES +=
libs
sdcv
endef

define UPDATE_GLOBAL_EXCLUDES +=
README.md
COPYING
LICENSE*
*license.txt
NOTICE
endef

.DEFAULT_GOAL := update

PHONY += xcode-prepare run

# Lua payload and linker inputs for the app. Xcode's pre-build phase runs this
# (platform/ios/scripts/xcode-prepare.sh), so Xcode and the fastlane lanes build what kodev builds.
# link.args loads all of koreader-base, LuaJIT and SDL3; dead-stripping keeps only what the app
# uses plus the exports, one per platform/ios/ffi-symbols.txt line. IOS_GATE_DROP=<symbol> leaves
# one out, to watch the symbol gate fail.
xcode-prepare: all
	/usr/bin/rsync -aL --delete --delete-excluded $(UPDATE_PATH_EXCLUDES:%=--exclude='/%') \
		$(UPDATE_GLOBAL_EXCLUDES:%=--exclude='%') $(INSTALL_DIR)/koreader/ $(IOS_PAYLOAD)/
	cp $(IOS_DIR)/ios-shim.lua $(IOS_PAYLOAD)/
	{ \
		echo '$(abspath $(OUTPUT_DIR))/libs/libkoreader-monolibtic.o'; \
		echo '-Wl,-force_load,$(abspath $(STAGING_DIR))/lib/libluajit-5.1.a'; \
		echo '-Wl,-force_load,$(abspath $(STAGING_DIR))/lib/libSDL3.a'; \
		sed -n 's/^Libs:.*-lSDL3//p' $(STAGING_DIR)/lib/pkgconfig/sdl3.pc; \
		echo '-lc++ -framework CoreFoundation'; \
	} >$(INSTALL_DIR)/link.args
	sed -e '/^#/d' -e '/^$$/d' $(if $(IOS_GATE_DROP),-e '/^$(IOS_GATE_DROP)$$/d') -e 's/^/_/' \
		$(IOS_DIR)/ffi-symbols.txt >$(INSTALL_DIR)/ffi-symbols.exp.tmp
	cmp -s $(INSTALL_DIR)/ffi-symbols.exp.tmp $(INSTALL_DIR)/ffi-symbols.exp \
		&& rm $(INSTALL_DIR)/ffi-symbols.exp.tmp \
		|| mv $(INSTALL_DIR)/ffi-symbols.exp.tmp $(INSTALL_DIR)/ffi-symbols.exp

update:
ifeq ($(IOS_PLATFORM), iphonesimulator)
	cd $(IOS_DIR) && mise exec -- tuist generate --no-open
	xcodebuild -workspace $(IOS_DIR)/JustReader.xcworkspace -scheme JustReader \
		-configuration $(IOS_CONFIGURATION) -sdk $(IOS_PLATFORM) -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath '$(IOS_DERIVED_DATA)' build $(if $(IOS_GATE_DROP),IOS_GATE_DROP=$(IOS_GATE_DROP))
else
	# The TestFlight build without the upload: fastlane signs from its dedicated keychain and
	# exports the App Store IPA (doc/ios/delivery.md); the gate then checks the stripped archive.
	cd $(IOS_DIR) && mise exec -- bundle exec fastlane ios build_release archive_path:'$(IOS_ARCHIVE)'
endif
	$(IOS_DIR)/scripts/check-symbols.sh '$(IOS_APP)' $(IOS_DIR)/ffi-symbols.txt $(IOS_DIR)/JustReader/Sources
	@echo 'Built $(IOS_APP)'

# Relative arguments are paths in the app's data container (which moves on every install),
# e.g. `./kodev run ios Documents/book.epub`.
run: update
	xcrun simctl install '$(IOS_SIMULATOR)' '$(IOS_APP)'
	container="$$(xcrun simctl get_app_container '$(IOS_SIMULATOR)' $(IOS_BUNDLE_ID) data)"; \
	for a in $(RARGS); do \
		[[ "$$a" = [-/]* ]] || a="$${container}/$$a"; \
		set -- "$$@" "$$a"; \
	done; \
	xcrun simctl launch --console-pty --terminate-running-process '$(IOS_SIMULATOR)' $(IOS_BUNDLE_ID) "$$@"
