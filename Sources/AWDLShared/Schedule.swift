import Foundation

/// A time window in which a fixed mode applies, e.g. block AWDL Mon-Fri 09:00-18:00.
/// A window whose end is not after its start runs past midnight (22:00-06:00) and belongs
/// to the day it starts on; equal start and end means 24 hours.
public struct ScheduleWindow: Codable, Equatable, Sendable {
    /// Calendar weekdays: 1 = Sunday ... 7 = Saturday.
    public var days: Set<Int>
    /// Minutes after midnight, 0-1440.
    public var start: Int
    public var end: Int
    public var mode: Mode

    public init(days: Set<Int> = Set(1...7), start: Int, end: Int, mode: Mode) {
        self.days = days
        self.start = start
        self.end = end
        self.mode = mode
    }

    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    /// Parses a profile entry: `Days` (optional, e.g. ["mon", "fri"]; default every day),
    /// `Start` and `End` ("HH:mm", End may be "24:00") and `Mode`. Returns nil if invalid.
    public init?(values: [String: Any]) {
        guard let mode = (values["Mode"] as? String).flatMap(Mode.init(parsing:)),
              let start = (values["Start"] as? String).flatMap(Self.minutes), start < 1440,
              let end = (values["End"] as? String).flatMap(Self.minutes) else { return nil }
        var days = Set(1...7)
        if let names = values["Days"] as? [String] {
            days = Set(names.compactMap { name in
                Self.dayNames.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
            })
            guard !days.isEmpty else { return nil }
        }
        self.init(days: days, start: start, end: end, mode: mode)
    }

    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...24).contains(h), (0...59).contains(m), h * 60 + m <= 1440 else { return nil }
        return h * 60 + m
    }

    /// When the window is active at `date`, the moment it ends; otherwise nil.
    public func end(ifActiveAt date: Date, calendar: Calendar = .current) -> Date? {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday, let hour = c.hour, let minute = c.minute else { return nil }
        let now = hour * 60 + minute
        let yesterday = weekday == 1 ? 7 : weekday - 1

        func at(_ minutes: Int, daysFromToday offset: Int) -> Date? {
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))
                .flatMap { calendar.date(byAdding: .minute, value: minutes, to: $0) }
        }

        if start < end {
            return days.contains(weekday) && now >= start && now < end ? at(end, daysFromToday: 0) : nil
        }
        if days.contains(weekday) && now >= start {
            return at(end, daysFromToday: 1)
        }
        if days.contains(yesterday) && now < end {
            return at(end, daysFromToday: 0)
        }
        return nil
    }
}

public struct ActiveScheduleWindow: Equatable, Sendable {
    public var window: ScheduleWindow
    public var until: Date
}
