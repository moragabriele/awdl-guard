import Foundation

public struct PolicyInput: Sendable {
    public var settings: Settings
    public var now: Date
    public var overrideUntil: Date?
    public var onWiFi: Bool
    public var reports: [ActivityReport]
    /// Last time any trigger was active; used to avoid flapping when a trigger ends.
    public var lastTriggerSeen: Date?

    public init(settings: Settings, now: Date = Date(), overrideUntil: Date? = nil, onWiFi: Bool,
                reports: [ActivityReport] = [], lastTriggerSeen: Date? = nil) {
        self.settings = settings
        self.now = now
        self.overrideUntil = overrideUntil
        self.onWiFi = onWiFi
        self.reports = reports
        self.lastTriggerSeen = lastTriggerSeen
    }
}

public struct PolicyDecision: Equatable, Sendable {
    public var allowAWDL: Bool
    public var reason: String
    public var activeTriggers: [String]
    public var activeExemptions: [String]

    public init(allowAWDL: Bool, reason: String, activeTriggers: [String], activeExemptions: [String] = []) {
        self.allowAWDL = allowAWDL
        self.reason = reason
        self.activeTriggers = activeTriggers
        self.activeExemptions = activeExemptions
    }
}

public enum Policy {
    public static func activeTriggers(settings: Settings, reports: [ActivityReport]) -> [String] {
        var triggers = Set<String>()
        let listed = Set(settings.triggerApps.map { $0.lowercased() })
        for r in reports {
            if settings.triggerOnMicrophone && r.microphoneInUse {
                triggers.insert("microphone")
            }
            if settings.triggerOnGames && r.frontmostIsGame {
                triggers.insert("game:\(r.frontmostBundleID ?? "unknown")")
            }
            guard !listed.isEmpty else { continue }
            let candidates: [String]
            switch settings.triggerAppsMatch {
            case .running: candidates = r.runningBundleIDs
            case .frontmost: candidates = r.frontmostBundleID.map { [$0] } ?? []
            }
            for id in candidates where listed.contains(id.lowercased()) {
                triggers.insert("app:\(id)")
            }
        }
        return triggers.sorted()
    }

    /// Running apps that keep AWDL available: the administrator's list, plus each user's own
    /// list (matched only against that user's apps) when user exemptions are allowed.
    public static func activeExemptions(settings: Settings, reports: [ActivityReport]) -> [String] {
        let admin = Set(settings.exemptApps.map { $0.lowercased() })
        var exemptions = Set<String>()
        for r in reports {
            var listed = admin
            if settings.allowUserExemptions {
                listed.formUnion(r.userExemptApps.map { $0.lowercased() })
            }
            guard !listed.isEmpty else { continue }
            for id in r.runningBundleIDs where listed.contains(id.lowercased()) {
                exemptions.insert(id)
            }
        }
        return exemptions.sorted()
    }

    public static func decide(_ input: PolicyInput) -> PolicyDecision {
        let s = input.settings
        let triggers = s.mode == .auto ? activeTriggers(settings: s, reports: input.reports) : []

        if let until = input.overrideUntil, until > input.now, s.allowUserOverride {
            return PolicyDecision(allowAWDL: true, reason: "temporarily allowed by user", activeTriggers: triggers)
        }
        if s.mode == .on {
            return PolicyDecision(allowAWDL: true, reason: "mode is on", activeTriggers: [])
        }
        let exemptions = activeExemptions(settings: s, reports: input.reports)
        if !exemptions.isEmpty {
            return PolicyDecision(allowAWDL: true, reason: "exempt app running", activeTriggers: triggers,
                                  activeExemptions: exemptions)
        }
        if s.onlyOnWiFi && !input.onWiFi {
            return PolicyDecision(allowAWDL: true, reason: "not using Wi-Fi", activeTriggers: triggers)
        }
        if s.mode == .off {
            return PolicyDecision(allowAWDL: false, reason: "mode is off", activeTriggers: [])
        }
        if !triggers.isEmpty {
            return PolicyDecision(allowAWDL: false, reason: "trigger active", activeTriggers: triggers)
        }
        if let last = input.lastTriggerSeen,
           input.now.timeIntervalSince(last) < TimeInterval(s.reenableDelaySeconds) {
            return PolicyDecision(allowAWDL: false, reason: "re-enable pending", activeTriggers: [])
        }
        return PolicyDecision(allowAWDL: true, reason: "no trigger active", activeTriggers: [])
    }
}
