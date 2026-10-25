import UIKit
import UniformTypeIdentifiers

// 导入's document picker (B3, Q10): copies of the picked files, which Lua moves into Documents.
// Lua polls (ADR-0009); nothing here calls back into Lua. Lua calls these on the main thread, SDL's.
@MainActor
private final class FilePicker: NSObject, UIDocumentPickerDelegate {
    static let shared = FilePicker()

    private var state = "idle"
    private var paths: [String] = []
    private var failures: [(name: String, reason: String)] = []
    private var error = ""
    private var snapshot: UnsafeMutablePointer<CChar>? // the last poll's text, valid until the next poll
    private weak var picker: UIDocumentPickerViewController?
    private var shown = Date.distantPast

    func start(_ extensions: [String]) -> Int32 {
        guard state != "pending" else { return 1 }
        guard let presenter = Self.topViewController() else { return 2 }
        // the last picker still on its way out: UIKit would refuse to present over it
        guard !presenter.isBeingDismissed else { return 1 }
        var types: [UTType] = []
        for ext in extensions {
            // "fb2.zip" is a zip file to the system
            if let last = ext.split(separator: ".").last, let type = UTType(filenameExtension: String(last)),
               !types.contains(type) {
                types.append(type)
            }
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types.isEmpty ? [.item] : types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        state = "pending"
        paths = []
        failures = []
        error = ""
        presenter.present(picker, animated: true)
        self.picker = picker
        shown = Date()
        return 0
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            if FileManager.default.isReadableFile(atPath: url.path) {
                paths.append(url.path)
            } else {
                // a cloud file the system could not bring to the device
                failures.append((url.lastPathComponent, "not_downloaded"))
            }
        }
        state = "picked"
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        state = "cancelled"
    }

    // One line per field: "state\t<state>", "path\t<path>", "fail\t<name>\t<reason>", "error\t<text>".
    // ponytail: a tab or newline inside a file name would split its line; take JSON if that ever shows up.
    func poll() -> UnsafePointer<CChar> {
        // a picker that went away without telling (or never showed): give up on it after a grace period,
        // as the share sheet does (B8), or every later tap would be "busy"
        if state == "pending", picker?.presentingViewController == nil, Date().timeIntervalSince(shown) > 3 {
            state = "cancelled"
        }
        var lines = ["state\t\(state)"]
        lines += paths.map { "path\t\($0)" }
        lines += failures.map { "fail\t\($0.name)\t\($0.reason)" }
        if !error.isEmpty { lines.append("error\t\(error)") }
        if state != "pending" && state != "idle" {
            state = "idle" // a final state is returned once
            paths = []
            failures = []
            error = ""
        }
        free(snapshot)
        snapshot = strdup(lines.joined(separator: "\n"))
        return UnsafePointer(snapshot!)
    }

    // SDL's view controller, or what it presents now.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// 0: shown, 1: one shows already, 2: no window to show it over. `extensions` is newline-separated.
@c(ko_ios_files_pick_start)
nonisolated public func ko_ios_files_pick_start(_ extensions: UnsafePointer<CChar>) -> Int32 {
    let list = String(cString: extensions).split(separator: "\n").map(String.init)
    return MainActor.assumeIsolated { FilePicker.shared.start(list) }
}

@c(ko_ios_files_pick_poll)
nonisolated public func ko_ios_files_pick_poll() -> UnsafePointer<CChar> {
    // a pointer isn't Sendable: it leaves the main actor as its address
    let address = MainActor.assumeIsolated { UInt(bitPattern: FilePicker.shared.poll()) }
    return UnsafePointer(bitPattern: address)!
}
