import Foundation

/// Odcinek snu sprowadzony do tego, co potrzebne do liczenia. Bez typów
/// HealthKit — dzięki temu cała matematyka snu chodzi w testach bez urządzenia.
struct SleepSegment: Sendable, Equatable {
    enum Stage: Sendable, Equatable {
        case rem, deep, core, unspecified, awake, inBed

        /// `inBed` i `awake` to nie sen. `inBed` z założenia nachodzi na fazy snu
        /// (Apple liczy je jako osobne pojęcie), więc wliczenie go zawyżałoby dobę.
        var isAsleep: Bool {
            switch self {
            case .rem, .deep, .core, .unspecified: true
            case .awake, .inBed: false
            }
        }
    }

    let stage: Stage
    let start: Date
    let end: Date

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

struct SleepSummary: Sendable, Equatable {
    let start: Date
    let end: Date
    let asleepMinutes: Int
    let remMinutes: Int
    let deepMinutes: Int
    let coreMinutes: Int
    let awakeMinutes: Int
}

enum SleepMath {
    /// Doba snu przypisana do dnia POBUDKI: 18:00 dnia poprzedniego → 12:00 dnia `date`.
    ///
    /// Noc 5→6 sierpnia jest snem „z 6 sierpnia". Okno węższe niż doba celowo:
    /// przy podziale południe-do-południa popołudniowa drzemka z 5-go wpadałaby
    /// do nocy 6-go. Praca zmianowa się w to nie łapie i to znany kompromis.
    static func window(forWakeDay date: Date, calendar: Calendar) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? startOfDay
        return DateInterval(start: start, end: end)
    }

    /// Okno liczenia SRI: równe `days` dób, od południa do południa. Podział
    /// w południe sprawia, że noc dzieli się tylko raz, a porównanie „ta sama
    /// minuta dobę wcześniej" wypada zawsze w środku snu, nie na jego granicy.
    static func regularityWindow(endingOn day: Date, days: Int, calendar: Calendar) -> DateInterval {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let start = calendar.date(byAdding: .day, value: -days, to: noon) ?? noon
        return DateInterval(start: start, end: noon)
    }

    /// Suma mnogościowa odcinków. HealthKit trzyma próbki z każdego źródła osobno,
    /// więc iPhone, Watch i aplikacja trzecia potrafią opisać tę samą noc trzy razy —
    /// zwykłe zsumowanie długości dałoby 20 godzin snu.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }

        var result: [DateInterval] = []
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, next.end))
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    static func minutes(_ intervals: [DateInterval]) -> Int {
        Int((merged(intervals).reduce(0) { $0 + $1.duration } / 60).rounded())
    }

    /// `nil`, gdy w oknie nie ma ani jednej próbki snu — noc bez zegarka na ręce
    /// ma zostać pusta, a nie wyzerowana.
    static func summarize(_ segments: [SleepSegment]) -> SleepSummary? {
        let asleep = merged(segments.filter { $0.stage.isAsleep }.map(\.interval))
        guard let first = asleep.first, let last = asleep.last else { return nil }

        let night = DateInterval(start: first.start, end: last.end)
        // Wybudzenia liczymy tylko w środku nocy. Próbka `awake` sprzed zaśnięcia
        // to jeszcze wieczór, nie fragmentacja snu.
        let awake = segments
            .filter { $0.stage == .awake }
            .compactMap { $0.interval.intersection(with: night) }

        func stageMinutes(_ stage: SleepSegment.Stage) -> Int {
            minutes(segments.filter { $0.stage == stage }.map(\.interval))
        }

        return SleepSummary(
            start: first.start,
            end: last.end,
            asleepMinutes: minutes(asleep),
            remMinutes: stageMinutes(.rem),
            deepMinutes: stageMinutes(.deep),
            coreMinutes: stageMinutes(.core),
            awakeMinutes: minutes(awake)
        )
    }

    /// Sleep Regularity Index — procent minut, w których stan sen/czuwanie zgadza
    /// się ze stanem dokładnie 24 h wcześniej, przeskalowany na -100…100
    /// (SRI = 2 × zgodność − 100). Mierzy REGULARNOŚĆ rytmu, nie długość snu:
    /// osiem godzin co noc o tej samej porze da ~90, ta sama ilość snu o losowych
    /// porach ~40.
    ///
    /// Zwraca `nil`, gdy okno jest krótsze niż dwie doby albo gdy dni bez danych
    /// jest za dużo — brak zegarka na ręce wygląda w danych jak całonocne czuwanie
    /// i zaniżyłby wynik bez żadnego powodu.
    static func regularityIndex(
        asleep: [DateInterval],
        window: DateInterval,
        calendar: Calendar,
        minimumDaysWithSleep: Int = 5
    ) -> Double? {
        let minutesInDay = 24 * 60
        let totalMinutes = Int(window.duration / 60)
        guard totalMinutes >= 2 * minutesInDay else { return nil }

        let clipped = merged(asleep).compactMap { $0.intersection(with: window) }
        guard !clipped.isEmpty else { return nil }

        let daysWithSleep = Set(clipped.map { calendar.startOfDay(for: $0.start) })
        guard daysWithSleep.count >= minimumDaysWithSleep else { return nil }

        var state = [Bool](repeating: false, count: totalMinutes)
        for interval in clipped {
            let from = Int(interval.start.timeIntervalSince(window.start) / 60)
            let to = Int((interval.end.timeIntervalSince(window.start) / 60).rounded(.up))
            for index in max(0, from)..<min(totalMinutes, to) {
                state[index] = true
            }
        }

        let comparisons = totalMinutes - minutesInDay
        var matches = 0
        for index in 0..<comparisons where state[index] == state[index + minutesInDay] {
            matches += 1
        }

        let agreement = Double(matches) / Double(comparisons)
        return ((200 * agreement - 100) * 100).rounded() / 100
    }
}
