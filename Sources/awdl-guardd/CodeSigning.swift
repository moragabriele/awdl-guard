import Foundation
import Security

enum CodeSigning {
    /// Team ID of the running binary, or nil for ad-hoc / unsigned development builds.
    static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Clients must be Developer ID signed by the same team as the daemon.
    static func clientRequirement(teamID: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
