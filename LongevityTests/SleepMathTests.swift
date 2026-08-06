import Foundation
import Testing

@testable import Longevity

@Suite("Matematyka snu")
struct SleepMathTests {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    /// "2026-08-06 23:30" → Date w strefie warszawskiej.
    private static func date(_ text: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    private static func segment(_ stage: SleepSegment.Stage, _ from: String, _ to: String) -> SleepSegment {
        SleepSegment(stage: stage, start: date(from), end: date(to))
    }

    // MARK: - Scalanie odcinków

    @Test("Nakładające się odcinki liczą się raz")
    func mergesOverlapping() {
        let ranges = [
            DateInterval(start: Self.date("2026-08-05 23:00"), end: Self.date("2026-08-06 03:00")),
            DateInterval(start: Self.date("2026-08-06 01:00"), end: Self.date("2026-08-06 05:00")),
        ]
        #expect(SleepMath.merged(ranges).count == 1)
        #expect(SleepMath.minutes(ranges) == 360)
    }

    @Test("Rozłączne odcinki zostają osobno")
    func keepsDisjoint() {
        let ranges = [
            DateInterval(start: Self.date("2026-08-05 23:00"), end: Self.date("2026-08-06 01:00")),
            DateInterval(start: Self.date("2026-08-06 02:00"), end: Self.date("2026-08-06 04:00")),
        ]
        #expect(SleepMath.merged(ranges).count == 2)
        #expect(SleepMath.minutes(ranges) == 240)
    }

    // MARK: - Podsumowanie nocy

    /// Regresja, której nie da się zauważyć bez drugiego źródła: iPhone i Watch
    /// opisują tę samą noc osobnymi próbkami. Zwykłe zsumowanie długości dałoby
    /// dwa razy więcej snu, niż użytkownik przespał.
    @Test("Duplikat z drugiego źródła nie podwaja doby")
    func doesNotDoubleCountSources() throws {
        let segments = [
            Self.segment(.core, "2026-08-05 23:00", "2026-08-06 03:00"),
            Self.segment(.core, "2026-08-05 23:00", "2026-08-06 03:00"),
            Self.segment(.rem, "2026-08-06 03:00", "2026-08-06 05:00"),
        ]
        let summary = try #require(SleepMath.summarize(segments))

        #expect(summary.asleepMinutes == 360)
        #expect(summary.coreMinutes == 240)
        #expect(summary.remMinutes == 120)
    }

    @Test("inBed nie jest snem")
    func ignoresInBed() throws {
        let segments = [
            Self.segment(.inBed, "2026-08-05 22:30", "2026-08-06 06:30"),
            Self.segment(.core, "2026-08-05 23:00", "2026-08-06 05:00"),
        ]
        let summary = try #require(SleepMath.summarize(segments))

        #expect(summary.asleepMinutes == 360)
        #expect(summary.start == Self.date("2026-08-05 23:00"))
        #expect(summary.end == Self.date("2026-08-06 05:00"))
    }

    /// Czuwanie przed zaśnięciem to jeszcze wieczór, nie fragmentacja snu —
    /// inaczej każdy, kto długo czyta w łóżku, wyglądałby na wybudzonego.
    @Test("Wybudzenia liczą się tylko w środku nocy")
    func clipsAwakeToNight() throws {
        let segments = [
            Self.segment(.awake, "2026-08-05 22:00", "2026-08-05 23:00"),
            Self.segment(.core, "2026-08-05 23:00", "2026-08-06 02:00"),
            Self.segment(.awake, "2026-08-06 02:00", "2026-08-06 02:20"),
            Self.segment(.rem, "2026-08-06 02:20", "2026-08-06 06:00"),
        ]
        let summary = try #require(SleepMath.summarize(segments))

        #expect(summary.awakeMinutes == 20)
    }

    @Test("Noc bez próbek snu daje nil, nie zero")
    func emptyNightIsNil() {
        #expect(SleepMath.summarize([]) == nil)
        #expect(SleepMath.summarize([Self.segment(.inBed, "2026-08-05 22:00", "2026-08-06 06:00")]) == nil)
    }

    // MARK: - Okno doby snu

    /// Noc 5→6 sierpnia jest snem "z 6 sierpnia" — tak samo pokazuje to Zdrowie.
    @Test("Doba snu należy do dnia pobudki")
    func windowBelongsToWakeDay() {
        let window = SleepMath.window(forWakeDay: Self.date("2026-08-06 09:00"), calendar: Self.calendar)

        #expect(window.start == Self.date("2026-08-05 18:00"))
        #expect(window.end == Self.date("2026-08-06 12:00"))
        #expect(window.contains(Self.date("2026-08-05 23:30")))
        #expect(window.contains(Self.date("2026-08-06 06:30")))
        #expect(!window.contains(Self.date("2026-08-05 14:00")))
    }

    // MARK: - Sleep Regularity Index

    private static func nights(_ count: Int, from firstBedtime: String, hours: Double = 8) -> [DateInterval] {
        let start = date(firstBedtime)
        return (0..<count).map { day in
            let bed = start.addingTimeInterval(Double(day) * 86_400)
            return DateInterval(start: bed, duration: hours * 3600)
        }
    }

    @Test("Stały rytm daje wynik bliski 100")
    func regularScheduleScoresHigh() throws {
        let window = DateInterval(
            start: Self.date("2026-07-29 12:00"),
            end: Self.date("2026-08-06 12:00")
        )
        let sri = try #require(
            SleepMath.regularityIndex(
                asleep: Self.nights(8, from: "2026-07-29 23:00"),
                window: window,
                calendar: Self.calendar
            )
        )
        #expect(sri > 95)
    }

    /// SRI mierzy regularność, nie ilość: te same osiem godzin snu, ale co noc
    /// o innej porze, musi wypaść wyraźnie gorzej.
    @Test("Ruchoma pora snu obniża wynik mimo tej samej długości")
    func shiftingScheduleScoresLower() throws {
        let window = DateInterval(
            start: Self.date("2026-07-29 12:00"),
            end: Self.date("2026-08-06 12:00")
        )
        let base = Self.date("2026-07-29 21:00")
        let offsets: [Double] = [0, 3, -1, 4, 1, 5, 2, 0]
        let irregular = offsets.enumerated().map { index, shift in
            DateInterval(
                start: base.addingTimeInterval(Double(index) * 86_400 + shift * 3600),
                duration: 8 * 3600
            )
        }

        let regular = try #require(
            SleepMath.regularityIndex(
                asleep: Self.nights(8, from: "2026-07-29 23:00"),
                window: window,
                calendar: Self.calendar
            )
        )
        let shifting = try #require(
            SleepMath.regularityIndex(asleep: irregular, window: window, calendar: Self.calendar)
        )

        #expect(shifting < regular - 20)
    }

    /// Zegarek zdjęty na tydzień wygląda w danych jak całonocne czuwanie.
    /// Wynik liczony z takiego okna byłby fikcją, więc ma go nie być.
    @Test("Za mało dni z danymi daje nil")
    func refusesOnPoorCoverage() {
        let window = DateInterval(
            start: Self.date("2026-07-29 12:00"),
            end: Self.date("2026-08-06 12:00")
        )
        let sri = SleepMath.regularityIndex(
            asleep: Self.nights(3, from: "2026-08-03 23:00"),
            window: window,
            calendar: Self.calendar
        )
        #expect(sri == nil)
    }

    @Test("Okno krótsze niż dwie doby daje nil")
    func refusesOnShortWindow() {
        let window = DateInterval(
            start: Self.date("2026-08-05 12:00"),
            end: Self.date("2026-08-06 12:00")
        )
        let sri = SleepMath.regularityIndex(
            asleep: Self.nights(1, from: "2026-08-05 23:00"),
            window: window,
            calendar: Self.calendar
        )
        #expect(sri == nil)
    }

    @Test("Okno SRI ma równe osiem dób, od południa do południa")
    func regularityWindowIsWholeDays() {
        let window = SleepMath.regularityWindow(
            endingOn: Self.date("2026-08-06 09:00"),
            days: 8,
            calendar: Self.calendar
        )

        #expect(window.end == Self.date("2026-08-06 12:00"))
        #expect(window.start == Self.date("2026-07-29 12:00"))
        #expect(window.duration == 8 * 86_400)
    }
}
