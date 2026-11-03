import Foundation

public enum Constants {
    public static let version = "0.3.1"

    /// Preferences domain. MDM profiles use it as PayloadType; local admins can use
    /// `sudo defaults write /Library/Preferences/<domain> <Key> <value>`.
    public static let preferencesDomain = "io.github.moragabriele.awdlguard"
    public static let machServiceName = "io.github.moragabriele.awdlguard.xpc"
    public static let daemonLabel = "io.github.moragabriele.awdlguard.daemon"
    public static let agentLabel = "io.github.moragabriele.awdlguard.agent"
    public static let agentBundleID = "io.github.moragabriele.awdlguard.agent"
    public static let logSubsystem = "io.github.moragabriele.awdlguard"
    /// Root-owned daemon state that must survive restarts (the user's chosen mode).
    public static let stateFile = "/Library/Application Support/AWDL Guard/state.plist"
}

public enum JSON {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
