import AppKit
import AWDLShared
import os
import UniformTypeIdentifiers

private let log = Logger(subsystem: Constants.logSubsystem, category: "agent")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let client = DaemonClient()
    private let activity = ActivityWatcher()
    private let notifier = Notifier()
    /// Length of the user's last temporary allow, reused by the notification's "Extend" button.
    private var lastOverrideMinutes: Int?
    private var settings = Settings.load()
    private var status: DaemonStatus?
    private var statusItem: NSStatusItem?
    private var shownSymbol: String?
    private var lastSentReport: ActivityReport?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        client.onDisconnect = { [weak self] in
            // The daemon lost our last report (restart, upgrade): resend it shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.lastSentReport = nil
                self?.sendReport()
            }
        }
        activity.onChange = { [weak self] in self?.sendReport() }
        notifier.onExtend = { [weak self] in
            guard let self else { return }
            self.requestOverride(minutes: self.lastOverrideMinutes ?? self.defaultOverrideMinutes)
        }
        activity.start()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        settings = Settings.load()
        updateStatusItemVisibility()
        lastSentReport = nil // periodic heartbeat
        sendReport()
    }

    // MARK: - Daemon

    private func sendReport() {
        let report = activity.current()
        guard report != lastSentReport, let data = try? JSON.encoder.encode(report) else {
            return refreshStatus()
        }
        lastSentReport = report
        client.proxy { error in log.error("report failed: \(error.localizedDescription, privacy: .public)") }?
            .report(activity: data) { [weak self] _ in
                DispatchQueue.main.async { self?.refreshStatus() }
            }
    }

    private func refreshStatus() {
        let proxy = client.proxy { [weak self] _ in
            DispatchQueue.main.async {
                self?.status = nil
                self?.updateIcon()
            }
        }
        proxy?.getStatus { [weak self] data in
            let s = data.flatMap { try? JSON.decoder.decode(DaemonStatus.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = s
                self.updateIcon()
                self.notifier.extendMinutes = self.lastOverrideMinutes ?? self.defaultOverrideMinutes
                self.notifier.update(status: s, settings: self.settings)
            }
        }
    }

    // MARK: - Menu bar

    private func updateStatusItemVisibility() {
        if settings.showMenuBarIcon, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
            shownSymbol = nil
            updateIcon()
        } else if !settings.showMenuBarIcon, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let state: String
        switch status?.awdlAllowed {
        case .some(true): state = "allowed"
        case .some(false): state = "held"
        case .none: state = "unreachable"
        }
        // Status refreshes every few seconds; touching the button each time makes AppKit
        // re-show hover UI wherever the pointer is. No tooltip: the menu already shows the state.
        guard state != shownSymbol else { return }
        shownSymbol = state
        if let allowed = status?.awdlAllowed {
            button.image = MenuBarIcon.image(heldDown: !allowed)
        } else {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle",
                                   accessibilityDescription: "AWDL Guard daemon not reachable")
            button.image?.isTemplate = true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        refreshStatus()

        guard let s = status else {
            menu.addItem(disabled("Daemon not running"))
            addFooter(to: menu)
            return
        }

        menu.addItem(disabled(s.awdlAllowed ? "AWDL: allowed" : "AWDL: held down"))
        menu.addItem(disabled("Reason: \(s.reason)"))
        if !s.activeTriggers.isEmpty {
            menu.addItem(disabled("Triggers: \(s.activeTriggers.map(Self.describe).joined(separator: ", "))"))
        }
        if !s.activeExemptions.isEmpty {
            menu.addItem(disabled("Excluded: \(s.activeExemptions.map(Self.appName).joined(separator: ", "))"))
        }
        if let until = s.scheduleUntil {
            let time = DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
            menu.addItem(disabled("Mode: \(Self.modeTitle(s.mode)) (scheduled until \(time))"))
        } else if s.modeChangeAllowed {
            let item = NSMenuItem(title: "Mode: \(Self.modeTitle(s.mode))", action: nil, keyEquivalent: "")
            item.submenu = modeMenu(status: s)
            menu.addItem(item)
        } else {
            menu.addItem(disabled("Mode: \(Self.modeTitle(s.mode))"))
        }
        menu.addItem(.separator())

        if let until = s.overrideUntil {
            let time = DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
            menu.addItem(action("End temporary allow (until \(time))", #selector(cancelOverride)))
        }
        if s.overrideAvailable && (!s.awdlAllowed || s.overrideUntil != nil) {
            // Picking a length while an allow is running restarts it from now.
            let item = NSMenuItem(title: "Allow AirDrop/AirPlay for", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for minutes in Policy.overrideChoices(maxMinutes: s.overrideMaxMinutes) {
                let choice = action(Self.duration(minutes), #selector(requestOverrideFromMenu(_:)))
                choice.representedObject = minutes
                sub.addItem(choice)
            }
            item.submenu = sub
            menu.addItem(item)
        }

        if s.userExemptionsAllowed || !s.exemptApps.isEmpty {
            let item = NSMenuItem(title: "Exclusions", action: nil, keyEquivalent: "")
            item.submenu = exclusionsMenu(status: s)
            menu.addItem(item)
        }

        if !s.managedKeys.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Settings managed by your organization"))
        }
        addFooter(to: menu)
    }

    private func addFooter(to menu: NSMenu) {
        guard settings.allowUserQuit else { return }
        menu.addItem(.separator())
        menu.addItem(action("Quit AWDL Guard", #selector(quit)))
    }

    // MARK: - Mode

    private static func modeTitle(_ mode: Mode) -> String {
        switch mode {
        case .auto: return "Auto (calls, games)"
        case .block: return "Always block AWDL"
        case .allow: return "Always allow AWDL"
        }
    }

    private func modeMenu(status s: DaemonStatus) -> NSMenu {
        let menu = NSMenu()
        for mode in Mode.allCases {
            let item = action(Self.modeTitle(mode), #selector(selectMode(_:)))
            item.representedObject = mode.rawValue
            item.state = s.mode == mode ? .on : .off
            menu.addItem(item)
        }
        if s.userMode != nil {
            menu.addItem(.separator())
            let item = action("Use default (\(Self.modeTitle(s.policyMode)))", #selector(selectMode(_:)))
            item.representedObject = "default"
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        client.proxy { _ in }?.setMode(raw) { [weak self] ok, message in
            if !ok { log.error("mode change refused: \(message, privacy: .public)") }
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    // MARK: - Exclusions

    /// Apps listed here keep AWDL available while they are running.
    private func exclusionsMenu(status s: DaemonStatus) -> NSMenu {
        let menu = NSMenu()
        for id in s.exemptApps {
            menu.addItem(disabled("\(Self.appName(id)) (managed)"))
        }

        guard s.userExemptionsAllowed else {
            return menu
        }
        let mine = Settings.loadUserExemptApps()
        for id in mine {
            let item = action(Self.appName(id), #selector(removeExemption(_:)))
            item.state = .on
            item.representedObject = id
            item.toolTip = "Click to remove"
            menu.addItem(item)
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }

        // A status menu does not activate us, so this is still the app the user was working in.
        if let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier,
           id != Bundle.main.bundleIdentifier,
           !mine.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
            let item = action("Add \(front.localizedName ?? id)", #selector(addExemption(_:)))
            item.representedObject = id
            menu.addItem(item)
        }
        menu.addItem(action("Choose App…", #selector(chooseExemption)))
        return menu
    }

    @objc private func addExemption(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        updateUserExemptions { $0.append(id) }
    }

    @objc private func removeExemption(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        updateUserExemptions { $0.removeAll { $0 == id } }
    }

    @objc private func chooseExemption() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.message = "Choose apps that keep AirDrop, AirPlay and Sidecar available while open"
        panel.prompt = "Exclude"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        updateUserExemptions { $0.append(contentsOf: ids) }
    }

    private func updateUserExemptions(_ change: (inout [String]) -> Void) {
        var apps = Settings.loadUserExemptApps()
        change(&apps)
        var seen = Set<String>()
        apps = apps.filter { seen.insert($0.lowercased()).inserted }
        Settings.saveUserExemptApps(apps)
        lastSentReport = nil
        sendReport()
    }

    private static func appName(_ bundleID: String) -> String {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        return url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    }

    private static func describe(_ trigger: String) -> String {
        if trigger == "microphone" { return "call / microphone" }
        if let id = trigger.split(separator: ":", maxSplits: 1).last, trigger.contains(":") {
            return appName(String(id))
        }
        return trigger
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private static func duration(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            return minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
        }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    private var defaultOverrideMinutes: Int {
        min(15, status?.overrideMaxMinutes ?? settings.overrideMaxMinutes)
    }

    @objc private func requestOverrideFromMenu(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        lastOverrideMinutes = minutes
        requestOverride(minutes: minutes)
    }

    private func requestOverride(minutes: Int) {
        client.proxy { _ in }?.requestOverride(minutes: minutes) { [weak self] ok, message in
            if !ok { log.error("override refused: \(message, privacy: .public)") }
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    @objc private func cancelOverride() {
        notifier.cancelOverrideWarning()
        client.proxy { _ in }?.cancelOverride { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
