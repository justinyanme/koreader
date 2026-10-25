import UIKit

// Share sheet bridge for device/sdl/iosnative/share.lua (ADR-0009/0010): Lua polls the state and
// removes the files itself; nothing calls back into Lua. One sheet at a time.
// Raw values must match the states table in share.lua.
enum ShareState: Int32 { case presenting = 0, completed, cancelled, failed }

private var shareHandle: Int32 = 0
private var shareState = ShareState.failed
// Held while presenting: UIKit starts a presentation from SDL's event pump only later, so a refused
// one (which never calls the completion handler) is only detectable from the poll.
private var shareSheet: UIViewController?
private var shareStarted = Date.distantPast
private let shareGrace: TimeInterval = 3

private func finishShare(_ state: ShareState) {
    shareState = state
    shareSheet = nil
}

// SDL's view controller, or whatever it currently presents.
private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}

@c(ko_ios_share_start)
nonisolated public func koIOSShareStart(_ paths: UnsafePointer<UnsafePointer<CChar>?>?, _ count: Int32) -> Int32 {
    let urls = (0..<Int(max(count, 0))).compactMap { index in
        paths?[index].map { URL(fileURLWithPath: String(cString: $0)) }
    }
    return MainActor.assumeIsolated {
        guard !urls.isEmpty, shareState != .presenting, let host = topViewController(),
              host.view.window != nil, !host.isBeingDismissed else { return 0 }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        // iPad presents it as a popover, which needs an anchor: the middle of SDL's view, no arrow.
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        shareHandle += 1
        let handle = shareHandle
        shareState = .presenting
        sheet.completionWithItemsHandler = { _, completed, _, error in
            MainActor.assumeIsolated {
                guard handle == shareHandle else { return }
                finishShare(error != nil ? .failed : completed ? .completed : .cancelled)
            }
        }
        shareSheet = sheet
        shareStarted = Date()
        host.present(sheet, animated: true)
        return handle
    }
}

@c(ko_ios_share_poll)
nonisolated public func koIOSSharePoll(_ handle: Int32) -> Int32 {
    MainActor.assumeIsolated {
        guard handle == shareHandle else { return -1 }
        if shareState == .presenting, let sheet = shareSheet, sheet.presentingViewController == nil,
           !sheet.isBeingPresented, Date().timeIntervalSince(shareStarted) > shareGrace {
            finishShare(.failed)
        }
        return shareState.rawValue
    }
}
