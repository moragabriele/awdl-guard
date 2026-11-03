import AWDLCore
import AWDLShared
import Foundation
import os

private let log = Logger(subsystem: Constants.logSubsystem, category: "daemon")

/// Owns all state. Every mutation happens on `queue`.
final class Daemon: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "\(Constants.daemonLabel).state")

    private let monitor: AWDLMonitor
    private let network: NetworkWatcher
    private let listener = NSXPCListener(machServiceName: Constants.machServiceName)
    private let teamID = CodeSigning.ownTeamIdentifier()

    private var settings = Settings()
    private var managedKeys: [String] = []
    /// Mode picked from the menu bar or awdl-guardctl; persisted in `Constants.stateFile`.
    private var userMode: Mode?
    private var reports: [ObjectIdentifier: ActivityReport] = [:]
    private var overrideUntil: Date?
    private var lastTriggerSeen: Date?
    private var decision = PolicyDecision(allowAWDL: true, reason: "starting", activeTriggers: [])
    // AWDLMonitor starts with AWDL enabled and does not touch the interface until told otherwise.
    private var appliedAllow = true

    private var timers: [DispatchSourceTimer] = []
    private var signalSources: [DispatchSourceSignal] = []

    init?(monitor: AWDLMonitor?) {
        guard let monitor else { return nil }
        self.monitor = monitor
        self.network = NetworkWatcher(queue: queue)
        super.init()
    }

    func start() {
        queue.sync {
            loadState()
            reloadSettings()
            network.onChange = { [weak self] onWiFi in
                log.info("Wi-Fi in use: \(onWiFi, privacy: .public)")
                self?.evaluate()
            }
            network.start()
            evaluate()
        }

        // Re-evaluate often (cheap, pure logic) so override expiry and re-enable delays are honoured;
        // re-read preferences less often since MDM changes are rare.
        timers.append(repeating(seconds: 5) { [weak self] in self?.evaluate() })
        timers.append(repeating(seconds: 30) { [weak self] in
            self?.reloadSettings()
            self?.evaluate()
        })

        installSignalHandlers()

        if let teamID {
            listener.setConnectionCodeSigningRequirement(CodeSigning.clientRequirement(teamID: teamID))
        } else {
            log.warning("Daemon is not Developer ID signed: accepting unsigned clients (development build)")
        }
        listener.delegate = self
        listener.resume()
        log.info("awdl-guardd \(Constants.version, privacy: .public) started")
    }

    // MARK: - State

    private func reloadSettings() {
        dispatchPrecondition(condition: .onQueue(queue))
        let new = Settings.load()
        managedKeys = Settings.managedKeys()
        if new != settings {
            log.info("Settings changed: mode=\(new.mode.rawValue, privacy: .public)")
            settings = new
        }
    }

    /// Settings with the mode actually in force (the user's choice when allowed).
    private var effective: Settings {
        var s = settings
        s.mode = Policy.effectiveMode(settings: settings, managedKeys: managedKeys, userMode: userMode)
        return s
    }

    private func loadState() {
        guard let data = FileManager.default.contents(atPath: Constants.stateFile),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = dict["UserMode"] as? String else { return }
        userMode = Mode(parsing: raw)
    }

    private func saveState() {
        let url = URL(fileURLWithPath: Constants.stateFile)
        do {
            if let userMode {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(
                    fromPropertyList: ["UserMode": userMode.rawValue], format: .xml, options: 0)
                try data.write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            log.error("Could not save state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func evaluate() {
        dispatchPrecondition(condition: .onQueue(queue))
        let now = Date()
        if let until = overrideUntil, until <= now {
            overrideUntil = nil
            log.info("User override expired")
        }

        let current = effective
        let triggers = current.mode == .auto
            ? Policy.activeTriggers(settings: current, reports: Array(reports.values))
            : []
        if !triggers.isEmpty {
            lastTriggerSeen = now
        }

        let new = Policy.decide(PolicyInput(
            settings: current, now: now, overrideUntil: overrideUntil, onWiFi: network.onWiFi,
            reports: Array(reports.values), lastTriggerSeen: lastTriggerSeen
        ))
        if new.allowAWDL != appliedAllow {
            let detail = new.activeExemptions.isEmpty ? new.activeTriggers : new.activeExemptions
            log.notice("AWDL \(new.allowAWDL ? "allowed" : "held down", privacy: .public): \(new.reason, privacy: .public) \(detail, privacy: .public)")
            monitor.awdlEnabled = new.allowAWDL
            appliedAllow = new.allowAWDL
        }
        decision = new
    }

    private func status() -> DaemonStatus {
        dispatchPrecondition(condition: .onQueue(queue))
        let iface: String
        switch AWDLMonitor.currentInterfaceState() {
        case .up: iface = "up"
        case .down: iface = "down"
        default: iface = "missing"
        }
        let current = effective
        return DaemonStatus(
            version: Constants.version, mode: current.mode, policyMode: settings.mode, userMode: userMode,
            modeChangeAllowed: Policy.userModeAllowed(settings: settings, managedKeys: managedKeys),
            awdlAllowed: decision.allowAWDL,
            interfaceState: iface, reason: decision.reason, activeTriggers: decision.activeTriggers,
            activeExemptions: decision.activeExemptions, exemptApps: settings.exemptApps,
            userExemptionsAllowed: settings.allowUserExemptions,
            onWiFi: network.onWiFi, overrideUntil: overrideUntil,
            overrideAvailable: settings.allowUserOverride && current.mode != .allow,
            overrideMaxMinutes: settings.overrideMaxMinutes, managedKeys: managedKeys,
            connectedAgents: reports.count
        )
    }

    // MARK: - Client requests (called by ClientSession)

    func handleStatus(reply: @escaping (Data?) -> Void) {
        queue.async { reply(try? JSON.encoder.encode(self.status())) }
    }

    func handleReport(_ report: ActivityReport, from client: ObjectIdentifier) {
        queue.async {
            guard self.reports[client] != report else { return }
            self.reports[client] = report
            self.evaluate()
        }
    }

    func handleDisconnect(_ client: ObjectIdentifier) {
        queue.async {
            if self.reports.removeValue(forKey: client) != nil {
                self.evaluate()
            }
        }
    }

    func handleOverride(minutes: Int, reply: @escaping (Bool, String) -> Void) {
        queue.async {
            guard self.settings.allowUserOverride else {
                return reply(false, "Temporary override is disabled by policy")
            }
            guard self.effective.mode != .allow else {
                return reply(false, "AWDL is already allowed")
            }
            let m = min(max(minutes, 1), self.settings.overrideMaxMinutes)
            self.overrideUntil = Date().addingTimeInterval(TimeInterval(m * 60))
            log.notice("User override granted for \(m) min")
            self.evaluate()
            reply(true, "AWDL allowed for \(m) min")
        }
    }

    func handleCancelOverride(reply: @escaping (Bool) -> Void) {
        queue.async {
            let had = self.overrideUntil != nil
            self.overrideUntil = nil
            self.evaluate()
            reply(had)
        }
    }

    func handleSetMode(_ raw: String, reply: @escaping (Bool, String) -> Void) {
        queue.async {
            guard Policy.userModeAllowed(settings: self.settings, managedKeys: self.managedKeys) else {
                return reply(false, "Changing the mode is disabled by policy")
            }
            if raw.lowercased() == "default" {
                self.userMode = nil
            } else if let mode = Mode(parsing: raw) {
                self.userMode = mode
            } else {
                return reply(false, "Unknown mode '\(raw)': use auto, block, allow or default")
            }
            self.saveState()
            log.notice("User mode set to \(self.userMode?.rawValue ?? "default", privacy: .public)")
            self.evaluate()
            reply(true, "Mode is now \(self.effective.mode.rawValue)")
        }
    }

    func handleReload(reply: @escaping (Bool) -> Void) {
        queue.async {
            self.reloadSettings()
            self.network.refresh()
            self.evaluate()
            reply(true)
        }
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = ClientSession(daemon: self, connection: connection)
        connection.exportedInterface = NSXPCInterface(with: AWDLGuardXPC.self)
        connection.exportedObject = session
        let id = ObjectIdentifier(session)
        connection.invalidationHandler = { [weak self] in self?.handleDisconnect(id) }
        connection.interruptionHandler = { [weak self] in self?.handleDisconnect(id) }
        connection.resume()
        return true
    }

    // MARK: - Lifecycle

    private func repeating(seconds: Int, _ handler: @escaping () -> Void) -> DispatchSourceTimer {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds), leeway: .seconds(1))
        t.setEventHandler(handler: handler)
        t.resume()
        return t
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            src.setEventHandler { [weak self] in self?.shutdown() }
            src.resume()
            signalSources.append(src)
        }
        signal(SIGHUP, SIG_IGN)
        let hup = DispatchSource.makeSignalSource(signal: SIGHUP, queue: queue)
        hup.setEventHandler { [weak self] in
            self?.reloadSettings()
            self?.evaluate()
        }
        hup.resume()
        signalSources.append(hup)
    }

    /// Always hand AWDL back to macOS before exiting (unload, uninstall, shutdown).
    private func shutdown() {
        log.notice("Shutting down, restoring AWDL")
        monitor.awdlEnabled = true
        monitor.invalidate()
        exit(0)
    }
}

/// One per XPC connection, so reports can be attributed to (and dropped with) their agent.
final class ClientSession: NSObject, AWDLGuardXPC {
    private weak var daemon: Daemon?
    private let pid: pid_t

    init(daemon: Daemon, connection: NSXPCConnection) {
        self.daemon = daemon
        self.pid = connection.processIdentifier
    }

    func getStatus(withReply reply: @escaping (Data?) -> Void) {
        guard let daemon else { return reply(nil) }
        daemon.handleStatus(reply: reply)
    }

    func report(activity: Data, withReply reply: @escaping (Bool) -> Void) {
        guard let daemon, let report = try? JSON.decoder.decode(ActivityReport.self, from: activity) else {
            return reply(false)
        }
        daemon.handleReport(report, from: ObjectIdentifier(self))
        reply(true)
    }

    func requestOverride(minutes: Int, withReply reply: @escaping (Bool, String) -> Void) {
        guard let daemon else { return reply(false, "daemon unavailable") }
        log.info("Override requested by pid \(self.pid)")
        daemon.handleOverride(minutes: minutes, reply: reply)
    }

    func cancelOverride(withReply reply: @escaping (Bool) -> Void) {
        guard let daemon else { return reply(false) }
        daemon.handleCancelOverride(reply: reply)
    }

    func reload(withReply reply: @escaping (Bool) -> Void) {
        guard let daemon else { return reply(false) }
        daemon.handleReload(reply: reply)
    }

    func setMode(_ mode: String, withReply reply: @escaping (Bool, String) -> Void) {
        guard let daemon else { return reply(false, "daemon unavailable") }
        log.info("Mode change to \(mode, privacy: .public) requested by pid \(self.pid)")
        daemon.handleSetMode(mode, reply: reply)
    }
}
