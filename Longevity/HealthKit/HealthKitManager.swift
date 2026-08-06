import Foundation
import HealthKit

/// Odczyt markerów longevity z HealthKit. Tylko czyta — apka nic do Zdrowia
/// nie zapisuje, więc zbiór `toShare` jest pusty i nie potrzebujemy
/// `NSHealthUpdateUsageDescription`.
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    /// `HKHealthStore` jest oznaczony jako `Sendable`, więc może przejść do
    /// handlerów, które HealthKit woła na własnej kolejce.
    private let store = HKHealthStore()

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Zgoda

    static let readTypes: Set<HKObjectType> = {
        var types = Set(quantityMetrics.map { HKQuantityType($0.identifier) as HKObjectType })
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKCategoryType(.appleStandHour))
        return types
    }()

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// HealthKit z zasady nie zdradza, czy użytkownik zgodził się na ODCZYT —
    /// inaczej sam brak danych zdradzałby diagnozę. Jedyne, czego można się
    /// dowiedzieć, to czy okno zgody było już pokazane.
    func hasRequestedAccess() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        return status == .unnecessary
    }

    // MARK: - Odczyt

    /// Zbiera metryki za ostatnie `days` dni (licząc dzisiaj). Zwraca tylko dni,
    /// w których cokolwiek zmierzono — puste i tak odrzuciłby serwer.
    ///
    /// Zapytania idą po kolei, bo pojedyncze trwa milisekundy, a błąd jednego
    /// typu (np. temperatura nadgarstka na starszym Watchu) nie może wywalić
    /// całej synchronizacji.
    func readMetrics(days: Int, calendar: Calendar = .current, now: Date = Date()) async throws -> [DailyHealthMetrics] {
        guard isAvailable else { throw HealthKitError.unavailable }

        let today = calendar.startOfDay(for: now)
        guard
            let firstDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: today),
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: today)
        else { throw HealthKitError.unavailable }

        let range = DateInterval(start: firstDay, end: endOfToday)
        let dayList = Self.days(in: range, calendar: calendar)

        var metrics = dayList.reduce(into: [String: DailyHealthMetrics]()) { result, day in
            result[HealthDates.day(day, calendar: calendar)] = DailyHealthMetrics(
                metricDate: HealthDates.day(day, calendar: calendar)
            )
        }

        for metric in Self.quantityMetrics {
            let values = (try? await dailyStatistics(metric, range: range, calendar: calendar)) ?? [:]
            for (day, value) in values {
                guard var entry = metrics[day] else { continue }
                metric.apply(&entry, value)
                metrics[day] = entry
            }
        }

        for (day, hours) in (try? await standHours(range: range, calendar: calendar)) ?? [:] {
            metrics[day]?.standHours = hours
        }

        await applySleep(to: &metrics, days: dayList, calendar: calendar)

        return dayList
            .compactMap { metrics[HealthDates.day($0, calendar: calendar)] }
            .filter { !$0.isEmpty }
    }

    // MARK: - Metryki ilościowe

    private enum Aggregation {
        /// Kroki, kalorie, minuty ruchu — dobę opisuje suma.
        case sum
        /// Tętno spoczynkowe, HRV, oddech, SpO2 — dobę opisuje średnia z pomiarów.
        case average
        /// VO2max, waga, skład ciała, temperatura — dobę opisuje ostatni pomiar,
        /// bo to stany, nie zdarzenia.
        case mostRecent

        var options: HKStatisticsOptions {
            switch self {
            case .sum: .cumulativeSum
            case .average: .discreteAverage
            case .mostRecent: .mostRecent
            }
        }
    }

    private struct QuantityMetric {
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let aggregation: Aggregation
        let apply: (inout DailyHealthMetrics, Double) -> Void

        init(
            _ identifier: HKQuantityTypeIdentifier,
            _ unit: HKUnit,
            _ aggregation: Aggregation,
            apply: @escaping (inout DailyHealthMetrics, Double) -> Void
        ) {
            self.identifier = identifier
            self.unit = unit
            self.aggregation = aggregation
            self.apply = apply
        }
    }

    /// Uderzenia serca i oddechy HealthKit trzyma w tej samej jednostce: count/min.
    private static let perMinute = HKUnit.count().unitDivided(by: .minute())

    private static let quantityMetrics: [QuantityMetric] = [
        // Wydolność i serce
        .init(.vo2Max, HKUnit(from: "ml/kg*min"), .mostRecent) { $0.vo2max = $1 },
        .init(.restingHeartRate, perMinute, .average) { $0.restingHeartRate = $1 },
        .init(.heartRateVariabilitySDNN, .secondUnit(with: .milli), .average) { $0.hrvSdnnMs = $1 },
        .init(.walkingHeartRateAverage, perMinute, .average) { $0.walkingHeartRate = $1 },

        // Ruch
        .init(.stepCount, .count(), .sum) { $0.steps = Int($1.rounded()) },
        .init(.appleExerciseTime, .minute(), .sum) { $0.exerciseMinutes = Int($1.rounded()) },
        .init(.activeEnergyBurned, .kilocalorie(), .sum) { $0.activeEnergyKcal = $1 },

        // Skład ciała
        .init(.bodyMass, .gramUnit(with: .kilo), .mostRecent) { $0.weightKg = $1 },
        // `.percent()` zwraca 0…1, a kolumna trzyma punkty procentowe.
        .init(.bodyFatPercentage, .percent(), .mostRecent) { $0.bodyFatPct = $1 * 100 },
        .init(.leanBodyMass, .gramUnit(with: .kilo), .mostRecent) { $0.leanBodyMassKg = $1 },
        // Obwód bioder nie ma odpowiednika w HealthKit — idzie tylko z czatu.
        .init(.waistCircumference, .meterUnit(with: .centi), .mostRecent) { $0.waistCm = $1 },

        // Regeneracja
        .init(.respiratoryRate, perMinute, .average) { $0.respiratoryRate = $1 },
        .init(.oxygenSaturation, .percent(), .average) { $0.spo2Pct = $1 * 100 },
        .init(.appleSleepingWristTemperature, .degreeCelsius(), .mostRecent) { $0.wristTemperatureC = $1 },
    ]

    private func dailyStatistics(
        _ metric: QuantityMetric,
        range: DateInterval,
        calendar: Calendar
    ) async throws -> [String: Double] {
        let store = self.store
        let unit = metric.unit
        let aggregation = metric.aggregation

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(metric.identifier),
                quantitySamplePredicate: HKQuery.predicateForSamples(
                    withStart: range.start,
                    end: range.end
                ),
                options: aggregation.options,
                anchorDate: range.start,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [:])
                    return
                }

                var values: [String: Double] = [:]
                collection.enumerateStatistics(from: range.start, to: range.end) { statistics, _ in
                    let quantity: HKQuantity? = switch aggregation {
                    case .sum: statistics.sumQuantity()
                    case .average: statistics.averageQuantity()
                    case .mostRecent: statistics.mostRecentQuantity()
                    }
                    guard let quantity else { return }
                    let day = HealthDates.day(statistics.startDate, calendar: calendar)
                    values[day] = quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: values)
            }

            store.execute(query)
        }
    }

    // MARK: - Godziny stania

    private func standHours(range: DateInterval, calendar: Calendar) async throws -> [String: Int] {
        let samples = try await categorySamples(.appleStandHour, range: range)
        let stood = HKCategoryValueAppleStandHour.stood.rawValue

        return samples.reduce(into: [String: Int]()) { result, sample in
            guard sample.value == stood else { return }
            result[HealthDates.day(sample.start, calendar: calendar), default: 0] += 1
        }
    }

    // MARK: - Sen

    /// Ile dni wstecz sięga okno liczenia SRI. Osiem dób daje siedem porównań
    /// „ta minuta vs ta sama minuta dobę wcześniej" — minimum, przy którym
    /// wskaźnik regularności cokolwiek znaczy.
    private static let regularityWindowDays = 8

    private func applySleep(
        to metrics: inout [String: DailyHealthMetrics],
        days: [Date],
        calendar: Calendar
    ) async {
        guard
            let firstDay = days.first,
            let lastDay = days.last,
            let historyStart = calendar.date(
                byAdding: .day,
                value: -Self.regularityWindowDays,
                to: firstDay
            )
        else { return }

        let fetchRange = DateInterval(
            start: SleepMath.window(forWakeDay: historyStart, calendar: calendar).start,
            end: SleepMath.window(forWakeDay: lastDay, calendar: calendar).end
        )

        guard let samples = try? await categorySamples(.sleepAnalysis, range: fetchRange) else { return }
        let segments = samples.compactMap(Self.sleepSegment)
        guard !segments.isEmpty else { return }

        let allAsleep = segments.filter { $0.stage.isAsleep }.map(\.interval)

        for day in days {
            let key = HealthDates.day(day, calendar: calendar)
            guard metrics[key] != nil else { continue }

            let window = SleepMath.window(forWakeDay: day, calendar: calendar)
            let inWindow = segments.compactMap { segment -> SleepSegment? in
                guard let clipped = segment.interval.intersection(with: window), clipped.duration > 0
                else { return nil }
                return SleepSegment(stage: segment.stage, start: clipped.start, end: clipped.end)
            }

            if let summary = SleepMath.summarize(inWindow) {
                metrics[key]?.sleepStartAt = HealthDates.iso(summary.start)
                metrics[key]?.sleepEndAt = HealthDates.iso(summary.end)
                metrics[key]?.sleepAsleepMinutes = summary.asleepMinutes
                metrics[key]?.sleepRemMinutes = summary.remMinutes
                metrics[key]?.sleepDeepMinutes = summary.deepMinutes
                metrics[key]?.sleepCoreMinutes = summary.coreMinutes
                metrics[key]?.sleepAwakeMinutes = summary.awakeMinutes
            }

            metrics[key]?.sleepRegularityIndex = SleepMath.regularityIndex(
                asleep: allAsleep,
                window: SleepMath.regularityWindow(
                    endingOn: day,
                    days: Self.regularityWindowDays,
                    calendar: calendar
                ),
                calendar: calendar
            )
        }
    }

    private static func sleepSegment(_ sample: CategorySample) -> SleepSegment? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }

        let stage: SleepSegment.Stage = switch value {
        case .inBed: .inBed
        case .asleepREM: .rem
        case .asleepDeep: .deep
        case .asleepCore: .core
        case .asleepUnspecified: .unspecified
        case .awake: .awake
        @unknown default: .unspecified
        }

        return SleepSegment(stage: stage, start: sample.start, end: sample.end)
    }

    // MARK: - Wspólne zapytanie o próbki kategorii

    private struct CategorySample: Sendable {
        let value: Int
        let start: Date
        let end: Date
    }

    private func categorySamples(
        _ identifier: HKCategoryTypeIdentifier,
        range: DateInterval
    ) async throws -> [CategorySample] {
        let store = self.store

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(identifier),
                predicate: HKQuery.predicateForSamples(withStart: range.start, end: range.end),
                limit: HKObjectQueryNoLimit,
                // Bez sortowania: `SleepMath.merged` i tak porządkuje odcinki,
                // a godziny stania grupujemy po dniu.
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let mapped = (samples ?? []).compactMap { sample -> CategorySample? in
                    guard let category = sample as? HKCategorySample else { return nil }
                    return CategorySample(
                        value: category.value,
                        start: category.startDate,
                        end: category.endDate
                    )
                }
                continuation.resume(returning: mapped)
            }

            store.execute(query)
        }
    }

    // MARK: - Pomocnicze

    private static func days(in range: DateInterval, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = range.start
        while cursor < range.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}

enum HealthKitError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "HealthKit jest niedostępny na tym urządzeniu."
        }
    }
}
