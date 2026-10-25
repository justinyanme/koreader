import UIKit

// Brightness bridge for device/sdl/iosnative/brightness.lua (ADR-0009/0010): 0...1, or -1 without
// a screen. The window scene's screen replaces UIScreen.main, deprecated since iOS 26. Lua calls
// these on the main thread, where SDL runs its UIKit loop.
func sceneScreen() -> UIScreen? {
    UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first?.screen
}

@c(ko_ios_brightness_get)
nonisolated public func koIOSBrightnessGet() -> Double {
    MainActor.assumeIsolated { sceneScreen().map { Double($0.brightness) } ?? -1 }
}

@c(ko_ios_brightness_set)
nonisolated public func koIOSBrightnessSet(_ value: Double) -> Bool {
    MainActor.assumeIsolated {
        guard let screen = sceneScreen() else { return false }
        screen.brightness = CGFloat(min(max(value, 0), 1))
        return true
    }
}
