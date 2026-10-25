// B5 lifecycle bridge. The launcher installs the watcher after SDL event init
// and before Lua starts. SDL owns the app/scene delegates; no callback enters Lua.
import Foundation
import UIKit

@MainActor
private enum Background {
    static var installed = false
    static var nextHandle: Int64 = 0
    static var handle: Int64 = 0
    // The watcher may expire before Lua gets to SDL_PollEvent. Keep that claim
    // even after the UIKit task ends, so Lua observes the original expiry.
    static var pendingClaim: Int64?
    static var task = UIBackgroundTaskIdentifier.invalid
    static var expired: Set<Int64> = []
    static var incomplete = false

    static func claim() -> Int64 {
        if let pending = pendingClaim {
            pendingClaim = nil
            return pending
        }
        return begin()
    }

    static func begin() -> Int64 {
        if task != .invalid { return handle }
        nextHandle += 1
        let candidate = nextHandle
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "Save reading state") {
            // UIKit calls the expiration handler on the main thread. End the
            // task here, without waiting for Lua to observe the sticky flag.
            MainActor.assumeIsolated {
                expired.insert(candidate)
                incomplete = true
                end(candidate)
            }
        }
        guard identifier != .invalid else { return 0 }
        handle = candidate
        task = identifier
        return candidate
    }

    static func end(_ requested: Int64) {
        guard requested != 0, requested == handle, task != .invalid else { return }
        let identifier = task
        task = .invalid
        handle = 0
        UIApplication.shared.endBackgroundTask(identifier)
    }

    static func observe(_ type: UInt32) {
        if type == SDL_EVENT_WILL_ENTER_BACKGROUND.rawValue || type == SDL_EVENT_DID_ENTER_BACKGROUND.rawValue {
            if pendingClaim == nil { pendingClaim = begin() }
        }
        // SDL_SendAppEvent only invokes watchers for these app notifications.
        // A marked user event avoids recursively watching our own envelope and
        // prevents unrelated SDL_EVENT_USER payloads from becoming app events.
        var queued = SDL_Event()
        queued.type = SDL_EVENT_USER.rawValue
        queued.user.windowID = 0x4B4F4935 // KOI5; base checks this envelope tag.
        queued.user.code = Int32(type)
        if !SDL_PushEvent(&queued) {
            incomplete = true
            end(handle)
            pendingClaim = nil
        }
    }

    static func install() -> Bool {
        if installed { return true }
        installed = SDL_AddEventWatch({ _, event in
            guard let event else { return true }
            let type = event.pointee.type
            if type >= SDL_EVENT_TERMINATING.rawValue && type <= SDL_EVENT_DID_ENTER_FOREGROUND.rawValue {
                // UIKit lifecycle delivery is on its main thread. Marshalling
                // other senders also serializes bridge state with expiry.
                onBackgroundMain { Background.observe(type) }
            }
            return true
        }, nil)
        return installed
    }
}

nonisolated private func onBackgroundMain<T: Sendable>(_ action: @MainActor @Sendable () -> T) -> T {
    if Thread.isMainThread { return MainActor.assumeIsolated { action() } }
    return DispatchQueue.main.sync { MainActor.assumeIsolated { action() } }
}

@c(ko_ios_background_install)
nonisolated public func backgroundInstall() -> Bool {
    onBackgroundMain { Background.install() }
}

@c(ko_ios_background_begin)
nonisolated public func backgroundBegin() -> Int64 {
    onBackgroundMain { Background.claim() }
}

@c(ko_ios_background_end)
nonisolated public func backgroundEnd(_ handle: Int64) {
    onBackgroundMain { Background.end(handle) }
}

@c(ko_ios_background_expired)
nonisolated public func backgroundExpired(_ handle: Int64) -> Bool {
    onBackgroundMain { Background.expired.contains(handle) }
}

@c(ko_ios_background_save_incomplete)
nonisolated public func backgroundSaveIncomplete() -> Bool {
    onBackgroundMain { Background.incomplete }
}

@c(ko_ios_background_set_save_incomplete)
nonisolated public func backgroundSetSaveIncomplete(_ incomplete: Bool) {
    onBackgroundMain { Background.incomplete = incomplete }
}
