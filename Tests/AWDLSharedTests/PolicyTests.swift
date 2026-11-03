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

    // MARK: - Schedule

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-11-02 is a Monday.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func scheduleParsing() {
        let w = ScheduleWindow(values: ["Days": ["Mon", "friday"], "Start": "09:00", "End": "18:30", "Mode": "block"])
        #expect(w == ScheduleWindow(days: [2, 6], start: 540, end: 1110, mode: .block))
        #expect(ScheduleWindow(values: ["Start": "00:00", "End": "24:00", "Mode": "allow"])?.days == Set(1...7))
        #expect(ScheduleWindow(values: ["Start": "9", "End": "18:00", "Mode": "block"]) == nil)
        #expect(ScheduleWindow(values: ["Start": "09:00", "End": "25:00", "Mode": "block"]) == nil)
        #expect(ScheduleWindow(values: ["Start": "09:00", "End": "18:00", "Mode": "bogus"]) == nil)
        #expect(ScheduleWindow(values: ["Days": ["xyz"], "Start": "09:00", "End": "18:00", "Mode": "block"]) == nil)
        let s = Settings(values: ["Schedule": [["Start": "09:00", "End": "18:00", "Mode": "block"], ["Start": "bad"]]])
        #expect(s.schedule.count == 1)
    }

    @Test func scheduleDaytimeWindow() {
        let w = ScheduleWindow(days: [2, 3, 4, 5, 6], start: 540, end: 1080, mode: .block)
        #expect(w.end(ifActiveAt: date(day: 2, 9), calendar: utc) == date(day: 2, 18))
        #expect(w.end(ifActiveAt: date(day: 2, 17, 59), calendar: utc) != nil)
        #expect(w.end(ifActiveAt: date(day: 2, 18), calendar: utc) == nil)
        #expect(w.end(ifActiveAt: date(day: 2, 8, 59), calendar: utc) == nil)
        #expect(w.end(ifActiveAt: date(day: 1, 12), calendar: utc) == nil) // Sunday
    }

    @Test func scheduleOvernightWindowBelongsToStartDay() {
        let friday = ScheduleWindow(days: [6], start: 1320, end: 360, mode: .allow)
        #expect(friday.end(ifActiveAt: date(day: 6, 23), calendar: utc) == date(day: 7, 6))
        #expect(friday.end(ifActiveAt: date(day: 7, 5), calendar: utc) == date(day: 7, 6))  // Saturday morning
        #expect(friday.end(ifActiveAt: date(day: 7, 23), calendar: utc) == nil)            // Saturday night
        #expect(friday.end(ifActiveAt: date(day: 6, 5), calendar: utc) == nil)             // Friday morning
    }

    @Test func scheduleWinsOverModeAndUserChoice() {
        let cal = Calendar.current
        let s = settings {
            $0.mode = .allow
            $0.schedule = [ScheduleWindow(days: [2], start: 540, end: 1080, mode: .block)]
        }
        let inside = date(day: 2, 10, calendar: cal)
        let outside = date(day: 2, 20, calendar: cal)
        #expect(Policy.effectiveMode(settings: s, managedKeys: [], userMode: .auto, now: inside) == .block)
        #expect(Policy.effectiveMode(settings: s, managedKeys: [], userMode: .auto, now: outside) == .auto)
        #expect(Policy.effectiveMode(settings: s, managedKeys: ["Mode"], userMode: .auto, now: outside) == .allow)
    }

    @Test func firstMatchingWindowWins() {
        let windows = [
            ScheduleWindow(days: [2], start: 720, end: 780, mode: .allow),
            ScheduleWindow(days: [2], start: 540, end: 1080, mode: .block),
        ]
        #expect(Policy.activeWindow(windows, at: date(day: 2, 12, 30), calendar: utc)?.window.mode == .allow)
        #expect(Policy.activeWindow(windows, at: date(day: 2, 14), calendar: utc)?.window.mode == .block)
    }
}
