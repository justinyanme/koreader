import UIKit

// VoiceOver overlay (C3, Q21): the elements Lua declares (device/sdl/iosaccessibility), as
// UIAccessibilityElements over SDL's view. An activation only queues for Lua's poll and wakes its input
// wait with an SDL user event; nothing here calls back into Lua (ADR-0009). Lua calls these on the main
// thread, SDL's, where UIKit calls the elements too.
@MainActor
private enum Accessibility {
    static var queue: [String] = []
    static var snapshot: UnsafeMutablePointer<CChar>? // the last poll's text, valid until the next poll

    // One line per element: x, y, w, h (screen pixels), "true" if adjustable, label, value.
    static func set(_ lines: String, generation: Int32, pixelWidth: Double, screenChanged: Bool) {
        guard let view = sdlView(), pixelWidth > 0 else { return }
        let scale = view.bounds.width / CGFloat(pixelWidth) // SDL draws the screen over the whole view
        var elements: [Element] = []
        for line in lines.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7, let x = Double(fields[0]), let y = Double(fields[1]),
                  let w = Double(fields[2]), let h = Double(fields[3]) else { continue }
            let element = Element(accessibilityContainer: view)
            element.generation = generation
            element.index = elements.count + 1
            element.accessibilityFrameInContainerSpace = CGRect(x: x, y: y, width: w, height: h)
                .applying(CGAffineTransform(scaleX: scale, y: scale))
            element.accessibilityTraits = fields[4] == "true" ? .adjustable : .button
            element.accessibilityLabel = fields[5]
            element.accessibilityValue = fields[6].isEmpty ? nil : fields[6]
            elements.append(element)
        }
        view.accessibilityElements = elements
        // the second evidence besides an accessibility inspector (C3 acceptance)
        print("[JustReader] a11y \(generation): " + elements.map { $0.accessibilityLabel ?? "" }.joined(separator: " | "))
        UIAccessibility.post(notification: screenChanged ? .screenChanged : .layoutChanged, argument: nil)
    }

    static func enqueue(_ generation: Int32, _ index: Int, _ action: String) {
        queue.append("\(generation)\t\(index)\t\(action)")
        var wake = SDL_Event()
        wake.type = SDL_EVENT_USER.rawValue
        wake.user.windowID = 0x4B4F4141 // KOAA: not the lifecycle envelope, so base only returns EINTR
        _ = SDL_PushEvent(&wake)
    }

    // One line per action: generation, element index (from 1), action.
    static func poll() -> UnsafePointer<CChar> {
        free(snapshot)
        snapshot = strdup(queue.joined(separator: "\n"))
        queue = []
        return UnsafePointer(snapshot!)
    }

    // SDL's view, under whatever it presents.
    private static func sdlView() -> UIView? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController?.view
    }
}

private final class Element: UIAccessibilityElement {
    var generation: Int32 = 0
    var index = 0

    override func accessibilityActivate() -> Bool {
        Accessibility.enqueue(generation, index, "activate")
        return true
    }

    override func accessibilityIncrement() {
        Accessibility.enqueue(generation, index, "increment")
    }

    override func accessibilityDecrement() {
        Accessibility.enqueue(generation, index, "decrement")
    }
}

@c(ko_ios_a11y_set)
nonisolated public func ko_ios_a11y_set(_ elements: UnsafePointer<CChar>, _ generation: Int32,
                                        _ pixelWidth: Double, _ screenChanged: Bool) {
    let lines = String(cString: elements)
    MainActor.assumeIsolated {
        Accessibility.set(lines, generation: generation, pixelWidth: pixelWidth, screenChanged: screenChanged)
    }
}

@c(ko_ios_a11y_poll)
nonisolated public func ko_ios_a11y_poll() -> UnsafePointer<CChar> {
    // a pointer isn't Sendable: it leaves the main actor as its address
    let address = MainActor.assumeIsolated { UInt(bitPattern: Accessibility.poll()) }
    return UnsafePointer(bitPattern: address)!
}
