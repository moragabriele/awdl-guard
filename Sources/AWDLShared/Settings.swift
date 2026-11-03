import Foundation

public enum Mode: String, Codable, CaseIterable, Sendable {
    /// Hold AWDL down only while a trigger is active (call, game, listed app).
    case auto
    /// Hold AWDL down at all times.
    case block
    /// Never touch AWDL (stock macOS behaviour).
    case allow

    /// Accepts the current names plus the 0.1.0 ones (`on` = allow, `off` = block).
    public init?(parsing value: String) {
        switch value.lowercased() {
        case "on": self = .allow
        case "off": self = .block
        default: self.init(rawValue: value.lowercased())
        }
    }
}

public enum TriggerAppsMatch: String, Codable, Sendable {
    case running
    case frontmost
}

/// Configuration read from the preferences domain. Managed (MDM) values win over
/// /Library/Preferences, which wins over the defaults below.
public struct Settings: Codable, Equatable, Sendable {
    public var mode: Mode = .auto
    /// Lets users pick the mode from the menu bar. nil (not set) means "yes, unless a
    /// profile enforces Mode"; see `Policy.userModeAllowed`.
    public var allowUserModeChange: Bool?
    public var triggerApps: [String] = []
    public var triggerAppsMatch: TriggerAppsMatch = .running
    public var triggerOnGames = true
    public var triggerOnMicrophone = true
    /// Apps that, while running, keep AWDL available in every mode (e.g. Sidecar or AirPlay workflows).
    public var exemptApps: [String] = []
    /// Lets users add their own exempt apps from the menu bar.
    public var allowUserExemptions = false
    public var onlyOnWiFi = true
    public var reenableDelaySeconds = 30
    public var allowUserOverride = true
    public var overrideMaxMinutes = 15
    public var showMenuBarIcon = true
    public var allowUserQuit = true
    /// Time windows with a fixed mode; inside one, it wins over Mode and the user's choice.
    public var schedule: [ScheduleWindow] = []

    public init() {}

    public enum Key: String, CaseIterable {
        case mode = "Mode"
        case allowUserModeChange = "AllowUserModeChange"
        case triggerApps = "TriggerApps"
        case triggerAppsMatch = "TriggerAppsMatch"
        case triggerOnGames = "TriggerOnGames"
        case triggerOnMicrophone = "TriggerOnMicrophone"
        case exemptApps = "ExemptApps"
        case allowUserExemptions = "AllowUserExemptions"
        case onlyOnWiFi = "OnlyOnWiFi"
        case reenableDelaySeconds = "ReenableDelaySeconds"
        case allowUserOverride = "AllowUserOverride"
        case overrideMaxMinutes = "OverrideMaxMinutes"
        case showMenuBarIcon = "ShowMenuBarIcon"
        case allowUserQuit = "AllowUserQuit"
        case schedule = "Schedule"
    }

    /// Builds settings from raw key/value pairs; unknown or mistyped values fall back to defaults.
    public init(values: [String: Any]) {
        func bool(_ k: Key) -> Bool? { (values[k.rawValue] as? NSNumber)?.boolValue }
        func int(_ k: Key) -> Int? { (values[k.rawValue] as? NSNumber)?.intValue }
        func string(_ k: Key) -> String? { (values[k.rawValue] as? String)?.lowercased() }

        if let v = string(.mode), let m = Mode(parsing: v) { mode = m }
        allowUserModeChange = bool(.allowUserModeChange)
        if let v = values[Key.triggerApps.rawValue] as? [String] { triggerApps = v }
        if let v = string(.triggerAppsMatch), let m = TriggerAppsMatch(rawValue: v) { triggerAppsMatch = m }
        if let v = bool(.triggerOnGames) { triggerOnGames = v }
        if let v = bool(.triggerOnMicrophone) { triggerOnMicrophone = v }
        if let v = values[Key.exemptApps.rawValue] as? [String] { exemptApps = v }
        if let v = bool(.allowUserExemptions) { allowUserExemptions = v }
        if let v = bool(.onlyOnWiFi) { onlyOnWiFi = v }
        if let v = int(.reenableDelaySeconds) { reenableDelaySeconds = min(max(v, 0), 3600) }
        if let v = bool(.allowUserOverride) { allowUserOverride = v }
        if let v = int(.overrideMaxMinutes) { overrideMaxMinutes = min(max(v, 1), 1440) }
        if let v = bool(.showMenuBarIcon) { showMenuBarIcon = v }
        if let v = bool(.allowUserQuit) { allowUserQuit = v }
        if let v = values[Key.schedule.rawValue] as? [[String: Any]] {
            schedule = v.compactMap(ScheduleWindow.init(values:))
        }
    }

    public static func load(domain: String = Constants.preferencesDomain) -> Settings {
        let d = domain as CFString
        CFPreferencesAppSynchronize(d)
        var values: [String: Any] = [:]
        for k in Key.allCases {
            if let v = CFPreferencesCopyAppValue(k.rawValue as CFString, d) {
                values[k.rawValue] = v
            }
        }
        return Settings(values: values)
    }

    /// The current user's own exempt apps, kept in their preferences. Only the agent reads
    /// or writes these; the daemon honours them only when `allowUserExemptions` is set.
    public static let userExemptAppsKey = "UserExemptApps"

    public static func loadUserExemptApps(domain: String = Constants.preferencesDomain) -> [String] {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(userExemptAppsKey as CFString, domain as CFString) as? [String] ?? []
    }

    public static func saveUserExemptApps(_ apps: [String], domain: String = Constants.preferencesDomain) {
        CFPreferencesSetAppValue(userExemptAppsKey as CFString, apps as CFArray, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    /// Keys enforced by a configuration profile.
    public static func managedKeys(domain: String = Constants.preferencesDomain) -> [String] {
        Key.allCases
            .filter { CFPreferencesAppValueIsForced($0.rawValue as CFString, domain as CFString) }
            .map(\.rawValue)
    }
}
