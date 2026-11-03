import AWDLShared
import Foundation
import Testing

private func settings(_ configure: (inout Settings) -> Void = { _ in }) -> Settings {
    var s = Settings()
    configure(&s)
    return s
}

@Suite struct PolicyTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func modeOnAlwaysAllows() {
        let d = Policy.decide(PolicyInput(settings: settings { $0.mode = .allow }, onWiFi: true,
                                          reports: [ActivityReport(microphoneInUse: true)]))
        #expect(d.allowAWDL)
    }

    @Test func modeOffHoldsDownOnWiFi() {
        let d = Policy.decide(PolicyInput(settings: settings { $0.mode = .block }, onWiFi: true))
        #expect(!d.allowAWDL)
    }

    @Test func onlyOnWiFiAllowsOnEthernet() {
        let d = Policy.decide(PolicyInput(settings: settings { $0.mode = .block }, onWiFi: false))
        #expect(d.allowAWDL)
        let d2 = Policy.decide(PolicyInput(settings: settings { $0.mode = .block; $0.onlyOnWiFi = false }, onWiFi: false))
        #expect(!d2.allowAWDL)
    }

    @Test func autoHoldsDownDuringCall() {
        let d = Policy.decide(PolicyInput(settings: settings(), now: now, onWiFi: true,
                                          reports: [ActivityReport(microphoneInUse: true)]))
        #expect(!d.allowAWDL)
        #expect(d.activeTriggers == ["microphone"])
    }

    @Test func autoMicrophoneTriggerCanBeDisabled() {
        let d = Policy.decide(PolicyInput(settings: settings { $0.triggerOnMicrophone = false }, onWiFi: true,
                                          reports: [ActivityReport(microphoneInUse: true)]))
        #expect(d.allowAWDL)
    }

    @Test func triggerAppsMatchRunningOrFrontmost() {
        let report = ActivityReport(frontmostBundleID: "com.apple.Safari", runningBundleIDs: ["us.zoom.xos"])
        let running = settings { $0.triggerApps = ["US.ZOOM.XOS"] }
        #expect(Policy.activeTriggers(settings: running, reports: [report]) == ["app:us.zoom.xos"])
        let frontmost = settings { $0.triggerApps = ["us.zoom.xos"]; $0.triggerAppsMatch = .frontmost }
        #expect(Policy.activeTriggers(settings: frontmost, reports: [report]).isEmpty)
    }

    @Test func gamesTriggerOnlyWhenFrontmost() {
        let report = ActivityReport(frontmostBundleID: "com.example.game", frontmostIsGame: true)
        #expect(Policy.activeTriggers(settings: settings(), reports: [report]) == ["game:com.example.game"])
    }

    @Test func reenableDelayPreventsFlapping() {
        let s = settings { $0.reenableDelaySeconds = 30 }
        let pending = Policy.decide(PolicyInput(settings: s, now: now, onWiFi: true,
                                                lastTriggerSeen: now.addingTimeInterval(-10)))
        #expect(!pending.allowAWDL)
        let done = Policy.decide(PolicyInput(settings: s, now: now, onWiFi: true,
                                             lastTriggerSeen: now.addingTimeInterval(-31)))
        #expect(done.allowAWDL)
    }

    @Test func overrideAllowsUntilExpiryUnlessPolicyForbids() {
        let off = settings { $0.mode = .block }
        let active = Policy.decide(PolicyInput(settings: off, now: now, overrideUntil: now.addingTimeInterval(60), onWiFi: true))
        #expect(active.allowAWDL)
        let expired = Policy.decide(PolicyInput(settings: off, now: now, overrideUntil: now.addingTimeInterval(-1), onWiFi: true))
        #expect(!expired.allowAWDL)
        let forbidden = Policy.decide(PolicyInput(settings: settings { $0.mode = .block; $0.allowUserOverride = false },
                                                  now: now, overrideUntil: now.addingTimeInterval(60), onWiFi: true))
        #expect(!forbidden.allowAWDL)
    }

    @Test func adminExemptionBeatsCallTriggerAndModeOff() {
        let report = ActivityReport(runningBundleIDs: ["com.example.sidecarapp"], microphoneInUse: true)
        let auto = Policy.decide(PolicyInput(settings: settings { $0.exemptApps = ["com.example.SidecarApp"] },
                                             onWiFi: true, reports: [report]))
        #expect(auto.allowAWDL)
        #expect(auto.activeExemptions == ["com.example.sidecarapp"])
        let off = Policy.decide(PolicyInput(settings: settings { $0.mode = .block; $0.exemptApps = ["com.example.sidecarapp"] },
                                            onWiFi: true, reports: [report]))
        #expect(off.allowAWDL)
    }

    @Test func exemptionOnlyWhileAppRuns() {
        let s = settings { $0.mode = .block; $0.exemptApps = ["com.example.sidecarapp"] }
        let d = Policy.decide(PolicyInput(settings: s, onWiFi: true, reports: [ActivityReport(runningBundleIDs: ["com.other"])]))
        #expect(!d.allowAWDL)
    }

    @Test func userExemptionsRequirePolicy() {
        let report = ActivityReport(runningBundleIDs: ["com.example.app"], microphoneInUse: true,
                                    userExemptApps: ["com.example.app"])
        let denied = Policy.decide(PolicyInput(settings: settings(), onWiFi: true, reports: [report]))
        #expect(!denied.allowAWDL)
        let allowed = Policy.decide(PolicyInput(settings: settings { $0.allowUserExemptions = true },
                                                onWiFi: true, reports: [report]))
        #expect(allowed.allowAWDL)
    }

    @Test func userExemptionsApplyOnlyToThatUsersApps() {
        let userA = ActivityReport(runningBundleIDs: [], userExemptApps: ["com.example.app"])
        let userB = ActivityReport(runningBundleIDs: ["com.example.app"], microphoneInUse: true)
        let d = Policy.decide(PolicyInput(settings: settings { $0.allowUserExemptions = true },
                                          onWiFi: true, reports: [userA, userB]))
        #expect(!d.allowAWDL)
    }

    @Test func reportFromOlderAgentDecodes() throws {
        let json = #"{"frontmostIsGame":false,"runningBundleIDs":[],"microphoneInUse":true}"#
        let r = try JSON.decoder.decode(ActivityReport.self, from: Data(json.utf8))
        #expect(r.userExemptApps.isEmpty)
        #expect(r.microphoneInUse)
    }

    @Test func settingsParsingFallsBackOnBadValues() {
        let s = Settings(values: [
            "Mode": "OFF",
            "TriggerApps": ["us.zoom.xos"],
            "OverrideMaxMinutes": NSNumber(value: 99_999),
            "OnlyOnWiFi": "not a bool",
            "TriggerAppsMatch": "bogus",
        ])
        #expect(s.mode == .block)
        #expect(s.triggerApps == ["us.zoom.xos"])
        #expect(s.overrideMaxMinutes == 1440)
        #expect(s.onlyOnWiFi == true)
        #expect(s.triggerAppsMatch == .running)
    }

    @Test func modeAcceptsNewNamesAndOldAliases() {
        #expect(Mode(parsing: "Block") == .block)
        #expect(Mode(parsing: "allow") == .allow)
        #expect(Mode(parsing: "off") == .block)
        #expect(Mode(parsing: "ON") == .allow)
        #expect(Mode(parsing: "bogus") == nil)
    }

    @Test func userMayChangeModeUnlessProfileEnforcesIt() {
        let s = settings { $0.mode = .auto }
        #expect(Policy.userModeAllowed(settings: s, managedKeys: []))
        #expect(!Policy.userModeAllowed(settings: s, managedKeys: ["Mode"]))
        let explicitYes = settings { $0.allowUserModeChange = true }
        #expect(Policy.userModeAllowed(settings: explicitYes, managedKeys: ["Mode"]))
        let explicitNo = settings { $0.allowUserModeChange = false }
        #expect(!Policy.userModeAllowed(settings: explicitNo, managedKeys: []))
    }

    @Test func effectiveModeUsesUserChoiceOnlyWhenAllowed() {
        let s = settings { $0.mode = .auto }
        #expect(Policy.effectiveMode(settings: s, managedKeys: [], userMode: .block) == .block)
        #expect(Policy.effectiveMode(settings: s, managedKeys: ["Mode"], userMode: .block) == .auto)
        #expect(Policy.effectiveMode(settings: s, managedKeys: [], userMode: nil) == .auto)
    }

    @Test func allowUserModeChangeParsing() {
        #expect(Settings(values: [:]).allowUserModeChange == nil)
        #expect(Settings(values: ["AllowUserModeChange": true]).allowUserModeChange == true)
    }
}
