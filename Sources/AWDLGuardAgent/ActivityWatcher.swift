import AppKit
import AWDLShared

/// Collects the per-user signals the root daemon cannot see: frontmost app, running
/// apps and microphone use.
final class ActivityWatcher {
    private let microphone = MicrophoneMonitor()

    var onChange: (() -> Void)?

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.onChange?() }
        }
        microphone.onChange = { [weak self] in self?.onChange?() }
        microphone.start()
    }

    func current() -> ActivityReport {
        let ws = NSWorkspace.shared
        let front = ws.frontmostApplication
        let running = ws.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
        return ActivityReport(
            frontmostBundleID: front?.bundleIdentifier,
            frontmostIsGame: front.map(Self.isGame) ?? false,
            runningBundleIDs: Array(Set(running)).sorted(),
            microphoneInUse: microphone.isInUse,
            userExemptApps: Settings.loadUserExemptApps()
        )
    }

    /// Same signals macOS uses to decide whether to offer Game Mode.
    static func isGame(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return false }
        return info["LSApplicationCategoryType"] as? String == "public.app-category.games"
            || info["LSSupportsGameMode"] as? Bool == true
    }
}
