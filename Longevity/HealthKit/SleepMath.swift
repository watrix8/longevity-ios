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

        /// Nazwa w ładunku wysyłanym na serwer. Musi się zgadzać z `ASLEEP_STAGES`
        /// w `lib/scoring-v3.ts` — to serwer rozstrzyga, co liczy się jako sen
        /// przy wyliczaniu SRI.
        var payloadName: String {
            switch self {
            case .rem: "rem"
            case .deep: "deep"
            case .core: "core"
            case .unspecified: "unspecified"
            case .awake: "awake"
            case .inBed: "inBed"
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
}
