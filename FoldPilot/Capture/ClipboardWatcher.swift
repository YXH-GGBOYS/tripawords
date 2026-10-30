import Observation
import OSLog
import UIKit

/// Polls the general pasteboard while the scene is in the foreground and hands newly copied
/// text to `onText`.
///
/// Reading `changeCount` and `hasStrings` never shows the paste permission prompt; only reading
/// `string` does. On a device set to "Ask" that read blocks while iOS shows "FoldPilot would
/// like to paste from …" on every copy, so a slow read is how we notice the setting is wrong.
@MainActor
@Observable
final class ClipboardWatcher {
    static let interval: TimeInterval = 0.4
    /// A read slower than this almost certainly waited on the permission prompt.
    static let promptThreshold: Duration = .milliseconds(350)

    private(set) var isRunning = false
    /// Set when a read looked like it waited on the paste prompt; the UI offers to fix the setting.
    var promptSuspected = false
    @ObservationIgnored var onText: ((String) -> Void)?

    // Seeded at launch so whatever was on the clipboard before the app opened is not looked up.
    // Not reset on start(): a word copied while we were in the background is picked up on return.
    @ObservationIgnored private var lastChangeCount = UIPasteboard.general.changeCount
    @ObservationIgnored private var timer: Timer?
    private let log = Logger(subsystem: "com.ggboys.foldpilot", category: "clipboard")

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        log.notice("watching, changeCount \(self.lastChangeCount)")
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        log.notice("stopped")
    }

    private func poll() {
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard pasteboard.hasStrings else { return }

        let started = ContinuousClock.now
        let text = pasteboard.string
        let elapsed = ContinuousClock.now - started
        if elapsed > Self.promptThreshold {
            promptSuspected = true
        }
        guard let text else {
            log.notice("change \(count): text not readable")
            return
        }
        log.notice("change \(count): \(text.count) chars read in \(elapsed)")
        onText?(text)
    }
}
