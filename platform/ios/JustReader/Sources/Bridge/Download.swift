import UIKit

// Download bridge for device/sdl/iosnative/download.lua (ADR-0009/0010): one GET per handle into the
// path Lua names, polled by Lua; nothing calls back into Lua. Redirects are never followed: a 3xx
// completes with its headers, and Lua's OPDSClient policy decides the next hop (ADR-0004, Q34).
// The body goes straight into that path (a data task, not a download task: a canceled download task
// leaves its own temporary file behind), so canceling or failing removes all of it.
// The session's delegate queue is the main queue, where Lua polls, so the jobs need no lock.
// No background session: while a download runs the app holds short background time, and when that
// runs out the downloads fail, so Lua shows a failure back in the foreground (Q12, Q28).

private final class DownloadJob {
    let path: String
    let task: URLSessionDataTask
    var file: FileHandle?
    var state = "pending" // pending, downloading, completed, failed, cancelled (iosbridge.lua)
    var received: Int64 = 0
    var total: Int64 = -1
    var status = 0
    var headers: [String: String] = [:]
    var error = ""

    init(path: String, task: URLSessionDataTask) {
        self.path = path
        self.task = task
    }

    var running: Bool { state == "pending" || state == "downloading" }

    func fail(_ text: String) {
        state = "failed"
        error = text.replacingOccurrences(of: "\n", with: " ")
        task.cancel()
        removeFile()
    }

    func removeFile() {
        try? file?.close()
        file = nil
        try? FileManager.default.removeItem(atPath: path)
    }
}

@MainActor private final class Downloads: NSObject, URLSessionDataDelegate {
    static let shared = Downloads()

    var jobs: [Int64: DownloadJob] = [:]
    var lastHandle: Int64 = 0
    var backgroundTask = UIBackgroundTaskIdentifier.invalid

    lazy var session: URLSession = {
        // Cookies, credentials and caching all belong to Lua: the session keeps none.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    func job(of task: URLSessionTask) -> DownloadJob? {
        jobs.values.first { $0.task === task }
    }

    // Background time while any download runs, released when none does.
    func updateBackgroundTime() {
        let running = jobs.values.contains { $0.running }
        if running, backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Downloads") { [self] in
                MainActor.assumeIsolated {
                    for job in jobs.values where job.running { job.fail("background") }
                    updateBackgroundTime()
                }
            }
        } else if !running, backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // Delegate callbacks come on the main queue (see session).

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                                completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil) // the 3xx itself is the answer
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                                completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        MainActor.assumeIsolated {
            guard let job = job(of: dataTask), job.running else { return completionHandler(.cancel) }
            guard FileManager.default.createFile(atPath: job.path, contents: nil),
                  let file = FileHandle(forWritingAtPath: job.path) else {
                job.fail("cannot write \(job.path)")
                return completionHandler(.cancel)
            }
            job.file = file
            job.state = "downloading"
            job.total = response.expectedContentLength // NSURLResponseUnknownLength is -1
            completionHandler(.allow)
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            guard let job = job(of: dataTask), job.running else { return }
            do {
                try job.file?.write(contentsOf: data)
                job.received += Int64(data.count)
            } catch {
                job.fail(error.localizedDescription)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            defer { updateBackgroundTime() }
            guard let job = job(of: task), job.running else { return }
            try? job.file?.close()
            job.file = nil
            if let error = error as? URLError {
                job.fail(error.code == .timedOut ? "timeout" : error.localizedDescription)
                return
            } else if let error {
                job.fail(error.localizedDescription)
                return
            }
            guard let response = task.response as? HTTPURLResponse else {
                job.fail("no HTTP response")
                return
            }
            job.status = response.statusCode
            for (name, value) in response.allHeaderFields {
                job.headers[String(describing: name).lowercased()] = String(describing: value)
                    .replacingOccurrences(of: "\n", with: " ")
            }
            job.state = "completed"
        }
    }
}

@c(ko_ios_download_start)
nonisolated public func koIOSDownloadStart(_ url: UnsafePointer<CChar>?, _ headers: UnsafePointer<CChar>?,
                                           _ path: UnsafePointer<CChar>?, _ timeout: Double) -> Int64 {
    guard let url, let path, let target = URL(string: String(cString: url)) else { return 0 }
    var request = URLRequest(url: target, timeoutInterval: timeout)
    // "Name: value\n" lines, as download.lua writes them.
    for line in (headers.map { String(cString: $0) } ?? "").split(separator: "\n") {
        guard let colon = line.firstIndex(of: ":") else { continue }
        // ponytail: Authorization is set by hand (Basic, from Lua's policy); Apple calls it reserved but
        // sends it. Move to a per-task credential only if a server ever sees it dropped.
        request.setValue(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces),
                         forHTTPHeaderField: String(line[..<colon]))
    }
    let file = String(cString: path)
    return MainActor.assumeIsolated {
        let downloads = Downloads.shared
        downloads.lastHandle += 1
        let task = downloads.session.dataTask(with: request)
        downloads.jobs[downloads.lastHandle] = DownloadJob(path: file, task: task)
        task.resume()
        downloads.updateBackgroundTime()
        return downloads.lastHandle
    }
}

// The state as download.lua parses it, malloc'd for Lua to free; NULL for an unknown handle.
@c(ko_ios_download_poll)
nonisolated public func koIOSDownloadPoll(_ handle: Int64) -> UnsafeMutablePointer<CChar>? {
    let text: String? = MainActor.assumeIsolated {
        guard let job = Downloads.shared.jobs[handle] else { return nil }
        // Lua may poll once more before the app is suspended: what it paints then never reaches the
        // screen, so a download stopped by the background stays "downloading" until the app is back.
        if job.error == "background", UIApplication.shared.applicationState != .active {
            return "downloading\n\(job.received)\n\(job.total)\n0\n\n"
        }
        var text = "\(job.state)\n\(job.received)\n\(job.total)\n\(job.status)\n\(job.error)\n"
        for (name, value) in job.headers { text += "\(name): \(value)\n" }
        return text
    }
    return text.flatMap { strdup($0) }
}

// Cancels and releases the job, removing its file, finished or not. Lua moves a book away first.
@c(ko_ios_download_cancel)
nonisolated public func koIOSDownloadCancel(_ handle: Int64) -> Bool {
    MainActor.assumeIsolated {
        let downloads = Downloads.shared
        guard let job = downloads.jobs.removeValue(forKey: handle) else { return true }
        job.task.cancel()
        job.removeFile()
        downloads.updateBackgroundTime()
        return true
    }
}
