import AWDLShared
import Foundation

let usage = """
usage: awdl-guardctl <command>

commands:
  status [--json]        show daemon state (use --json for MDM inventory scripts)
  mode <auto|block|allow|default>
                         choose the mode if policy permits; "default" goes back to the policy's
  allow [minutes]        temporarily allow AWDL (AirDrop, AirPlay, Sidecar...) if policy permits
  cancel                 end a temporary allow
  reload                 re-read preferences now
  settings               print effective settings and which keys are managed
  version
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    exit(1)
}

func printStatus(_ s: DaemonStatus) {
    let df = DateFormatter()
    df.timeStyle = .short
    print("AWDL:          \(s.awdlAllowed ? "allowed" : "held down") (\(s.reason))")
    print("awdl0:         \(s.interfaceState)")
    let source = s.userMode != nil && s.mode == s.userMode ? "chosen by user" : "policy"
    print("Mode:          \(s.mode.rawValue) (\(source)\(s.modeChangeAllowed ? "" : ", locked"))")
    print("Wi-Fi in use:  \(s.onWiFi ? "yes" : "no")")
    print("Triggers:      \(s.activeTriggers.isEmpty ? "none" : s.activeTriggers.joined(separator: ", "))")
    print("Exemptions:    \(s.activeExemptions.isEmpty ? "none" : s.activeExemptions.joined(separator: ", "))")
    if let until = s.overrideUntil {
        print("Override:      until \(df.string(from: until))")
    }
    print("Agents:        \(s.connectedAgents)")
    print("Managed keys:  \(s.managedKeys.isEmpty ? "none" : s.managedKeys.joined(separator: ", "))")
    print("Version:       \(s.version)")
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail(usage) }
let client = DaemonClient()

switch command {
case "status":
    let result: Result<Data?, DaemonClientError> = client.sync { p, done in p.getStatus(withReply: done) }
    switch result {
    case .failure(let error):
        if args.contains("--json") {
            print(#"{"error":"\#(error.description)"}"#)
        }
        fail(error.description)
    case .success(let data):
        guard let data, let status = try? JSON.decoder.decode(DaemonStatus.self, from: data) else {
            fail("invalid status from daemon")
        }
        if args.contains("--json") {
            print(String(decoding: data, as: UTF8.self))
        } else {
            printStatus(status)
        }
    }

case "allow":
    let minutes = args.count > 1 ? Int(args[1]) ?? 0 : 15
    guard minutes > 0 else { fail("minutes must be a positive integer") }
    let result: Result<(Bool, String), DaemonClientError> = client.sync { p, done in
        p.requestOverride(minutes: minutes) { ok, msg in done((ok, msg)) }
    }
    switch result {
    case .failure(let error): fail(error.description)
    case .success(let (ok, msg)):
        guard ok else { fail(msg) }
        print(msg)
    }

case "mode":
    guard args.count > 1 else { fail("usage: awdl-guardctl mode <auto|block|allow|default>") }
    let result: Result<(Bool, String), DaemonClientError> = client.sync { p, done in
        p.setMode(args[1]) { ok, msg in done((ok, msg)) }
    }
    switch result {
    case .failure(let error): fail(error.description)
    case .success(let (ok, msg)):
        guard ok else { fail(msg) }
        print(msg)
    }

case "cancel":
    let result: Result<Bool, DaemonClientError> = client.sync { p, done in p.cancelOverride(withReply: done) }
    if case .failure(let error) = result { fail(error.description) }
    print("Override cleared")

case "reload":
    let result: Result<Bool, DaemonClientError> = client.sync { p, done in p.reload(withReply: done) }
    if case .failure(let error) = result { fail(error.description) }
    print("Preferences reloaded")

case "settings":
    let data = (try? JSON.encoder.encode(Settings.load())) ?? Data()
    print(String(decoding: data, as: UTF8.self))
    let managed = Settings.managedKeys()
    print("Managed keys: \(managed.isEmpty ? "none" : managed.joined(separator: ", "))")

case "version", "--version":
    print(Constants.version)

default:
    fail(usage)
}
