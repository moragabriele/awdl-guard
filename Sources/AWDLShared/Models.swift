import Foundation

/// What a logged-in user's agent sees. Sent to the daemon; never leaves the Mac.
public struct ActivityReport: Codable, Equatable, Sendable {
    public var frontmostBundleID: String?
    public var frontmostIsGame: Bool
    public var runningBundleIDs: [String]
    public var microphoneInUse: Bool
    /// Apps this user chose to exempt; applied only if policy allows user exemptions.
    public var userExemptApps: [String]

    public init(frontmostBundleID: String? = nil, frontmostIsGame: Bool = false,
                runningBundleIDs: [String] = [], microphoneInUse: Bool = false,
                userExemptApps: [String] = []) {
        self.frontmostBundleID = frontmostBundleID
        self.frontmostIsGame = frontmostIsGame
        self.runningBundleIDs = runningBundleIDs
        self.microphoneInUse = microphoneInUse
        self.userExemptApps = userExemptApps
    }

    private enum CodingKeys: String, CodingKey {
        case frontmostBundleID, frontmostIsGame, runningBundleIDs, microphoneInUse, userExemptApps
    }

    // Tolerates reports from an older agent that has no userExemptApps.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frontmostBundleID = try c.decodeIfPresent(String.self, forKey: .frontmostBundleID)
        frontmostIsGame = try c.decode(Bool.self, forKey: .frontmostIsGame)
        runningBundleIDs = try c.decode([String].self, forKey: .runningBundleIDs)
        microphoneInUse = try c.decode(Bool.self, forKey: .microphoneInUse)
        userExemptApps = try c.decodeIfPresent([String].self, forKey: .userExemptApps) ?? []
    }
}

public struct DaemonStatus: Codable, Sendable {
    public var version: String
    public var mode: Mode
    public var awdlAllowed: Bool
    /// "up", "down" or "missing" (no Wi-Fi hardware / interface not created yet).
    public var interfaceState: String
    public var reason: String
    public var activeTriggers: [String]
    public var activeExemptions: [String]
    /// Exempt apps set by the administrator.
    public var exemptApps: [String]
    public var userExemptionsAllowed: Bool
    public var onWiFi: Bool
    public var overrideUntil: Date?
    public var overrideAvailable: Bool
    public var overrideMaxMinutes: Int
    public var managedKeys: [String]
    public var connectedAgents: Int

    public init(version: String, mode: Mode, awdlAllowed: Bool, interfaceState: String, reason: String,
                activeTriggers: [String], activeExemptions: [String], exemptApps: [String],
                userExemptionsAllowed: Bool, onWiFi: Bool, overrideUntil: Date?, overrideAvailable: Bool,
                overrideMaxMinutes: Int, managedKeys: [String], connectedAgents: Int) {
        self.version = version
        self.mode = mode
        self.awdlAllowed = awdlAllowed
        self.interfaceState = interfaceState
        self.reason = reason
        self.activeTriggers = activeTriggers
        self.activeExemptions = activeExemptions
        self.exemptApps = exemptApps
        self.userExemptionsAllowed = userExemptionsAllowed
        self.onWiFi = onWiFi
        self.overrideUntil = overrideUntil
        self.overrideAvailable = overrideAvailable
        self.overrideMaxMinutes = overrideMaxMinutes
        self.managedKeys = managedKeys
        self.connectedAgents = connectedAgents
    }
}
