import AWDLShared
import Foundation
import os
import UserNotifications

private let log = Logger(subsystem: Constants.logSubsystem, category: "notifications")

/// Turns daemon status changes into user notifications, as far as settings allow.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let extendAction = "extend"
    private static let overrideCategory = "override"
    private static let warningID = "override-warning"

    /// Called when the user picks "Extend" on an override notification.
    var onExtend: (() -> Void)?
    /// Minutes offered by the "Extend" button: the length the user last picked.
    var extendMinutes = 15 {
        didSet { if extendMinutes != oldValue && authorizationRequested { registerCategories() } }
    }

    private let center = UNUserNotificationCenter.current()
    private var authorizationRequested = false
    private var last: DaemonStatus?
    private var scheduledWarningFor: Date?

    override init() {
        super.init()
        center.delegate = self
    }

    /// Feed every status the agent receives. The first one only sets the baseline.
    func update(status s: DaemonStatus?, settings: Settings) {
        defer { last = s ?? last }
        guard let s else { return }
        requestAuthorizationIfNeeded(settings)
        guard let previous = last else {
            scheduleOverrideWarning(s, settings)
            return
        }

        if settings.notifyOnSchedule && s.scheduleUntil != previous.scheduleUntil {
            if let until = s.scheduleUntil {
                post("schedule", "Scheduled: \(Self.modeName(s.mode))", "Until \(Self.time(until)).")
            } else if previous.scheduleUntil != nil {
                post("schedule", "Schedule ended", "Back to \(Self.modeName(s.mode)).")
            }
        }

        scheduleOverrideWarning(s, settings)
        if settings.notifyOnOverrideEnd, let ended = previous.overrideUntil, s.overrideUntil == nil,
           ended <= Date().addingTimeInterval(10), !s.awdlAllowed {
            post("override-ended", "AirDrop and AirPlay are off again", "The temporary allow has ended.",
                 category: s.overrideAvailable ? Self.overrideCategory : nil)
        }

        if settings.notifyOnAWDLChange && s.awdlAllowed != previous.awdlAllowed {
            post("awdl", s.awdlAllowed ? "AWDL allowed" : "AWDL held down",
                 s.awdlAllowed ? "AirDrop and AirPlay are available." : "Reason: \(s.reason).")
        }
    }

    /// Forget a pending "ends in 1 minute" warning (the user ended the allow).
    func cancelOverrideWarning() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.warningID])
        scheduledWarningFor = nil
    }

    // MARK: - Private

    private func scheduleOverrideWarning(_ s: DaemonStatus, _ settings: Settings) {
        guard s.overrideUntil != scheduledWarningFor else { return }
        cancelOverrideWarning()
        guard settings.notifyOnOverrideEnd, let until = s.overrideUntil else { return }
        let delay = until.timeIntervalSinceNow - 60
        guard delay > 1 else { return }
        let content = Self.content("AirDrop and AirPlay turn off in 1 minute",
                                   "The temporary allow ends at \(Self.time(until)).",
                                   category: Self.overrideCategory)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.warningID, content: content, trigger: trigger))
        scheduledWarningFor = until
    }

    private func requestAuthorizationIfNeeded(_ settings: Settings) {
        guard !authorizationRequested,
              settings.notifyOnOverrideEnd || settings.notifyOnSchedule || settings.notifyOnAWDLChange else { return }
        authorizationRequested = true
        registerCategories()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                log.info("Notifications not allowed by the user")
            }
        }
    }

    private func registerCategories() {
        let extend = UNNotificationAction(identifier: Self.extendAction, title: "Extend \(extendMinutes) min")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.overrideCategory, actions: [extend], intentIdentifiers: []),
        ])
    }

    private func post(_ id: String, _ title: String, _ body: String, category: String? = nil) {
        // Same identifier replaces an older notification of the same kind instead of piling up.
        center.add(UNNotificationRequest(identifier: id, content: Self.content(title, body, category: category),
                                         trigger: nil))
    }

    private static func content(_ title: String, _ body: String, category: String?) -> UNNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        if let category { c.categoryIdentifier = category }
        return c
    }

    private static func time(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private static func modeName(_ mode: Mode) -> String {
        switch mode {
        case .auto: return "AWDL held down during calls and games"
        case .block: return "AWDL always held down"
        case .allow: return "AWDL always allowed"
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == Self.extendAction {
            DispatchQueue.main.async { self.onExtend?() }
        }
        completionHandler()
    }
}
