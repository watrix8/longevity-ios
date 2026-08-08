import Foundation

/// Arytmetyka na gołych datach („2026-08-08"), wspólna dla Dashboardu
/// i Trendów.
///
/// Kalendarz w UTC, bo daty nie niosą godziny — przy lokalnej strefie
/// przesunięcie o dzień potrafi wypaść na 23:00 dnia poprzedniego i zgubić
/// cały dzień w oknie. Format ISO sortuje się leksykograficznie, więc
/// porównania zakresów robimy wprost na łańcuchach.
enum CalendarDays {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static func date(fromISO iso: String) -> Date? { formatter.date(from: iso) }

    static func isoString(_ date: Date) -> String { formatter.string(from: date) }

    /// Data przesunięta o `days` dni. `nil` tylko przy dacie nie do sparsowania.
    static func shifted(_ iso: String, by days: Int) -> String? {
        guard let date = date(fromISO: iso),
              let moved = calendar.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return isoString(moved)
    }

    /// Ile dni kalendarza dzieli dwie daty.
    static func days(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
