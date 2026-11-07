import AppKit
import Foundation

// URLSession owns streaming downloads. Metadata and packages both have hard
// byte limits; redirects may only stay on GitHub's HTTPS download hosts.
final class UpdateDownload: NSObject, URLSessionDownloadDelegate {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var received = false
    private let destination: URL
    private let limit: Int64
    private let progress: (Double) -> Void

    init(destination: URL, limit: Int64, progress: @escaping (Double) -> Void) {
        self.destination = destination; self.limit = limit; self.progress = progress
    }
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        if url.host == "raw.githubusercontent.com" {
            return ["arm64", "x86_64"].compactMap { Appcast.url(for: $0) }.contains(url)
        }
        return ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }
    func cancel() {
        lock.lock(); cancelled = true; let running = task; lock.unlock()
        running?.cancel()
    }
    func fetch(_ url: URL) async throws {
        guard Self.allowed(url) else { throw UpdateFailure.download }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 30
                config.timeoutIntervalForResource = 20 * 60
                config.httpShouldSetCookies = false
                config.urlCredentialStorage = nil
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url)
                request.setValue("Neylu-Updater", forHTTPHeaderField: "User-Agent")
                let task = session.downloadTask(with: request)
                lock.lock(); self.task = task; let cancelled = self.cancelled; lock.unlock()
                if cancelled { task.cancel() }
                task.resume()
            }
        }, onCancel: { self.cancel() })
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allowed) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= limit, totalBytesExpectedToWrite <= limit else {
            failure = UpdateFailure.download; downloadTask.cancel(); return
        }
        progress(min(1, Double(totalBytesWritten) / Double(max(1, limit))))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let response = downloadTask.response as? HTTPURLResponse
            let status = response?.statusCode
            if status == 429 || (status == 403 && response?.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
                throw UpdateFailure.rateLimited
            }
            guard status == 200,
                  let count = try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber,
                  count.int64Value > 0, count.int64Value <= limit else { throw UpdateFailure.download }
            try FileManager.default.moveItem(at: location, to: destination)
            received = true
        } catch { failure = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error> = (failure ?? error).map { .failure($0) } ?? (received ? .success(()) : .failure(UpdateFailure.download))
        let continuation = self.continuation
        self.continuation = nil
        lock.lock(); self.task = nil; lock.unlock()
        session.finishTasksAndInvalidate()
        self.session = nil
        continuation?.resume(with: result)
    }
}

@MainActor
final class UpdateController: NSObject, NSWindowDelegate {
    var onDiscovery: ((AvailableUpdate?) -> Void)?
    private var window: NSWindow?
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let content = NSStackView()
    private var upToDate = false
    private var failure: Error?
    private var manualInstallation = false
    private var messageKey = ""
    private var messageArgument: String?
    private let status = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let action = NSButton()
    private let secondary = NSButton()
    private let website = NSButton()
    private let notes = NSTextView()
    private var task: Task<Void, Never>?
    private var available: AvailableUpdate?
    private var working = false
    private var temporary: URL?
    private let current = Bundle.main.object(forInfoDictionaryKey: "NeyluReleaseVersion") as? String ?? ""
    #if arch(arm64)
    nonisolated static let architecture = "arm64"
    #else
    nonisolated static let architecture = "x86_64"
    #endif

    func present() {
        if window == nil { makeWindow() }
        refreshLanguage()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !working { check() }
    }
    private func makeWindow() {
        let window = UtilityWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 156),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        let icon = NSImageView()
        icon.image = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Neylu")
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        status.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 11.5)
        subtitle.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [status, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 6
        let header = NSStackView(views: [icon, labels])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16
        labels.widthAnchor.constraint(equalToConstant: 300).isActive = true
        status.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        subtitle.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        progress.style = .bar
        progress.minValue = 0; progress.maxValue = 1
        progress.isHidden = true
        notes.frame = NSRect(x: 0, y: 0, width: 372, height: 150)
        notes.minSize = .zero
        notes.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        notes.isVerticallyResizable = true
        notes.isHorizontallyResizable = false
        notes.autoresizingMask = [.width]
        notes.textContainer?.widthTracksTextView = true
        notes.isEditable = false
        notes.isSelectable = true
        notes.drawsBackground = false
        notes.textContainerInset = NSSize(width: 0, height: 4)
        notes.textContainer?.lineFragmentPadding = 0
        notes.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        scroll.documentView = notes
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.isHidden = true
        action.target = self; action.action = #selector(performAction)
        action.bezelStyle = .rounded
        action.keyEquivalent = "\r"
        secondary.target = self; secondary.action = #selector(performSecondary)
        secondary.bezelStyle = .rounded
        secondary.keyEquivalent = "\u{1b}"
        website.title = L("link.github_releases")
        website.target = self; website.action = #selector(openReleases)
        website.isBordered = false
        website.font = .systemFont(ofSize: 11)
        website.contentTintColor = .linkColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [website, spacer, secondary, action])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        content.setViews([header, progress, scroll, buttons], in: .leading)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        content.detachesHiddenViews = true
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            progress.widthAnchor.constraint(equalTo: content.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 150),
            buttons.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
    }
    private func fitWindow() {
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let height = max(144, content.fittingSize.height + 44)
        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 420, height: height))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    // Keep native controls intact while updating all owned text on a language change.
    func refreshLanguage() {
        guard window != nil else { return }
        window?.title = L("update.title")
        website.title = L("link.github_releases")
        status.stringValue = messageArgument.map { String(format: L(messageKey), $0) } ?? L(messageKey)
        if let failure {
            subtitle.stringValue = UpdateFailure.describe(failure, language: AppLanguage.load())
        } else if manualInstallation {
            subtitle.stringValue = L("update.manual_install_hint")
        } else { subtitle.stringValue = String(format: L("update.current_version_format"), current) }
        action.isHidden = working || manualInstallation
        secondary.isHidden = upToDate
        if upToDate { action.title = L("action.ok") }
        else if failure != nil { action.title = available == nil ? L("update.action.check_again") : L("update.action.retry") }
        else if available != nil { action.title = UpdateFiles.canReplace(Bundle.main.bundleURL) ? L("update.action.install") : L("update.action.download_installer") }
        else { action.title = L("update.action.check_again") }
        secondary.title = working ? L("action.cancel") : (manualInstallation ? L("action.ok") : (available != nil && failure == nil ? L("update.action.later") : L("action.close")))
        if let available {
            notes.textStorage?.setAttributedString(ReleaseNotesRenderer.render(available.releaseNotes(language: AppLanguage.load())))
        }
        fitWindow()
    }
    private func setWorking(_ value: Bool, message: String, argument: String? = nil) {
        working = value
        messageKey = message
        messageArgument = argument
        progress.isHidden = !value
        progress.isIndeterminate = true
        if value { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        action.isEnabled = !value
        refreshLanguage()
    }
    private func check() {
        available = nil
        upToDate = false
        failure = nil
        manualInstallation = false
        scroll.isHidden = true
        setWorking(true, message: "update.status.checking")
        task = Task {
            do {
                guard let version = ReleaseVersion(current) else { throw UpdateFailure.metadata }
                available = try await UpdateDiscovery.find(current: version, architecture: Self.architecture)
                onDiscovery?(available)
                if let update = available {
                    setWorking(false, message: "update.status.available_format", argument: update.version.text)
                    scroll.isHidden = update.notes.isEmpty
                } else {
                    upToDate = true
                    setWorking(false, message: "update.status.up_to_date")
                }
                fitWindow()
            } catch { failed(error) }
        }
    }
    @objc private func openReleases() {
        NSWorkspace.shared.open(available?.page ?? URL(string: AvailableUpdate.repository + "/releases")!)
    }
    @objc private func performAction() {
        if upToDate { window?.close() }
        else if let update = available { install(update) } else { check() }
    }
    @objc private func performSecondary() {
        task?.cancel()
        window?.close()
    }
    func windowWillClose(_ notification: Notification) { task?.cancel() }
    private func failed(_ error: Error) {
        failure = error
        setWorking(false, message: "update.status.failed")
        scroll.isHidden = true
        temporary.map { try? FileManager.default.removeItem(at: $0) }
        temporary = nil
        fitWindow()
    }
    private func install(_ update: AvailableUpdate) {
        failure = nil
        manualInstallation = false
        scroll.isHidden = true
        setWorking(true, message: "update.status.downloading")
        task = Task { [self] in
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Neylu-update-" + UUID().uuidString)
                temporary = folder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let package = folder.appendingPathComponent(update.filename)
                try await UpdateDownload(destination: package, limit: update.size, progress: { [weak owner = self] fraction in
                    DispatchQueue.main.async {
                        owner?.progress.isIndeterminate = false
                        owner?.progress.doubleValue = fraction
                    }
                }).fetch(update.package)
                try Task.checkCancellation()
                setWorking(true, message: "update.status.preparing")
                // Hashing, mounting, copying and code validation never block UI sampling.
                let target = Bundle.main.bundleURL
                let prepared = try await Task.detached { () -> URL? in
                    try update.verify(package: package)
                    guard UpdateFiles.canReplace(target) else { return nil }
                    return try Self.prepare(update, package: package, target: target, folder: folder)
                }.value
                if Task.isCancelled {
                    if let prepared { try? FileManager.default.removeItem(at: prepared) }
                    throw CancellationError()
                }
                guard let stage = prepared else {
                    guard NSWorkspace.shared.open(package) else { throw UpdateFailure.operation }
                    manualInstallation = true
                    setWorking(false, message: "update.status.manual_install")
                    // Finder needs the DMG after this window closes. Only the
                    // verified package remains in the system temporary folder.
                    temporary = nil
                    fitWindow()
                    return
                }
                let process = Process()
                process.executableURL = stage.appendingPathComponent("NeyluUpdater")
                process.arguments = [target.path, String(ProcessInfo.processInfo.processIdentifier), update.version.text,
                                     Self.architecture, folder.path, AppLanguage.load().resolved().rawValue]
                do { try process.run() }
                catch { try? FileManager.default.removeItem(at: stage); throw error }
                let ready = stage.appendingPathComponent("ready")
                let deadline = Date().addingTimeInterval(30)
                while !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline && process.isRunning {
                    do { try await Task.sleep(nanoseconds: 100_000_000) }
                    catch { process.terminate(); try? FileManager.default.removeItem(at: stage); throw error }
                }
                guard FileManager.default.fileExists(atPath: ready.path) else {
                    process.terminate()
                    try? FileManager.default.removeItem(at: stage)
                    throw UpdateFailure.operation
                }
                temporary = nil // Installer owns cleanup from here on.
                NSApp.terminate(nil) // Normal termination flushes history first.
            } catch { failed(error) }
        }
    }
    nonisolated private static func prepare(_ update: AvailableUpdate, package: URL, target: URL, folder: URL) throws -> URL {
        let mount = folder.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)
        try UpdateFiles.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, package.path])
        defer { _ = try? UpdateFiles.run("/usr/bin/hdiutil", ["detach", mount.path]) }
        let stage = target.deletingLastPathComponent().appendingPathComponent(".Neylu-update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let candidate = stage.appendingPathComponent("Neylu.app")
            try UpdateFiles.run("/usr/bin/ditto", [mount.appendingPathComponent("Neylu.app").path, candidate.path])
            try UpdateFiles.validate(candidate, version: update.version, architecture: architecture, requiredTeam: UpdateFiles.signingTeam(target))
            let resources = stage.appendingPathComponent("Resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: false)
            for language in ["en", "zh-Hans"] {
                try FileManager.default.copyItem(at: target.appendingPathComponent("Contents/Resources/" + language + ".lproj"),
                                                to: resources.appendingPathComponent(language + ".lproj"))
            }
            // Copy the currently trusted helper, never a helper from the download.
            _ = try UpdateFiles.stageUpdater(from: target, in: stage)
            return stage
        } catch { try? FileManager.default.removeItem(at: stage); throw error }
    }
}
