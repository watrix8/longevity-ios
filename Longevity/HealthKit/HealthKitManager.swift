import Foundation
import HealthKit

@MainActor
final class HealthKitManager: Sendable {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        let readTypes: Set<HKSampleType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
        ]

        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func readRestingHeartRate() async throws -> Double? {
        // TODO: Implement query
        nil
    }

    func readStepCount(for date: Date) async throws -> Double? {
        // TODO: Implement query
        nil
    }

    func readSleepAnalysis(for date: Date) async throws -> TimeInterval? {
        // TODO: Implement query
        nil
    }

    func readHRV() async throws -> Double? {
        // TODO: Implement query
        nil
    }
}
