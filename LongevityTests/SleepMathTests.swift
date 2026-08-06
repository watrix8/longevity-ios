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

    /// Starsze zegarki i część aplikacji trzecich nie rozbijają snu na fazy,
    /// tylko piszą jeden odcinek `asleepUnspecified`. Taka noc musi liczyć się
    /// jako przespana, choć REM i deep wyjdą zerowe.
    @Test("Sen bez rozbicia na fazy liczy się jako sen")
    func unspecifiedCountsAsSleep() throws {
        let summary = try #require(
            SleepMath.summarize([Self.segment(.unspecified, "2026-08-05 23:00", "2026-08-06 06:30")])
        )

        #expect(summary.asleepMinutes == 450)
        #expect(summary.remMinutes == 0)
        #expect(summary.deepMinutes == 0)
        #expect(summary.coreMinutes == 0)
    }

    @Test("Fazy sumują się do całości snu")
    func stagesAddUp() throws {
        let segments = [
            Self.segment(.core, "2026-08-05 23:00", "2026-08-06 01:00"),
            Self.segment(.deep, "2026-08-06 01:00", "2026-08-06 02:00"),
            Self.segment(.rem, "2026-08-06 02:00", "2026-08-06 03:00"),
        ]
        let summary = try #require(SleepMath.summarize(segments))

        #expect(summary.asleepMinutes == 240)
        #expect(summary.coreMinutes + summary.deepMinutes + summary.remMinutes == 240)
    }

    @Test("Przerwa w środku nocy nie jest doliczana do snu")
    func gapIsNotSleep() throws {
        let segments = [
            Self.segment(.core, "2026-08-05 23:00", "2026-08-06 01:00"),
            Self.segment(.core, "2026-08-06 02:00", "2026-08-06 05:00"),
        ]
        let summary = try #require(SleepMath.summarize(segments))

        // Okno nocy to 6 h, ale przespane są 5 h.
        #expect(summary.asleepMinutes == 300)
        #expect(summary.start == Self.date("2026-08-05 23:00"))
        #expect(summary.end == Self.date("2026-08-06 05:00"))
    }

    /// Drzemka z popołudnia poprzedniego dnia nie należy do nocy — okno zaczyna
    /// się o 18:00 właśnie po to.
    @Test("Drzemka sprzed okna nie wchodzi do doby snu")
    func napBeforeWindowIsExcluded() {
        let window = SleepMath.window(forWakeDay: Self.date("2026-08-06 09:00"), calendar: Self.calendar)
        let nap = Self.segment(.core, "2026-08-05 14:00", "2026-08-05 15:30")

        #expect(nap.interval.intersection(with: window) == nil)
    }

    /// Odcinek zaczęty przed 18:00 ma wejść do nocy częścią po 18:00, a nie
    /// wypaść w całości — inaczej ktoś, kto zasnął przed telewizorem, gubi sen.
    @Test("Odcinek na granicy okna wchodzi przyciętą częścią")
    func segmentClippedAtWindowEdge() throws {
        let window = SleepMath.window(forWakeDay: Self.date("2026-08-06 09:00"), calendar: Self.calendar)
        let long = Self.segment(.core, "2026-08-05 17:00", "2026-08-05 20:00")
        let clipped = try #require(long.interval.intersection(with: window))

        #expect(clipped.start == Self.date("2026-08-05 18:00"))
        #expect(clipped.duration == 2 * 3600)
    }

    @Test("Odcinek o zerowej długości jest pomijany")
    func zeroLengthIgnored() {
        let zero = DateInterval(start: Self.date("2026-08-06 02:00"), end: Self.date("2026-08-06 02:00"))

        #expect(SleepMath.merged([zero]).isEmpty)
        #expect(SleepMath.minutes([zero]) == 0)
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
}
