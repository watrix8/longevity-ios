import Foundation
import Testing

@testable import Longevity

@Suite("Plan synchronizacji")
struct HealthSyncPlanTests {
    private static let now = Date(timeIntervalSince1970: 1_785_100_800)

    @Test("Pierwszy sync ciąga pełny backfill")
    func firstRunBackfills() {
        #expect(
            HealthSyncPlan.next(lastSyncedAt: nil, now: Self.now, automatic: true)
                == .sync(days: HealthSyncPlan.backfillDays)
        )
        #expect(
            HealthSyncPlan.next(lastSyncedAt: nil, now: Self.now, automatic: false)
                == .sync(days: HealthSyncPlan.backfillDays)
        )
    }

    /// Automat odpala się przy każdym powrocie apki na wierzch, więc bez
    /// odstępu odczytywałby HealthKit kilkanaście razy przy jednym przełączeniu
    /// się między apkami.
    @Test("Automat odpuszcza, gdy poprzedni sync był niedawno")
    func automaticRespectsInterval() {
        let recent = Self.now.addingTimeInterval(-600)

        #expect(HealthSyncPlan.next(lastSyncedAt: recent, now: Self.now, automatic: true) == .skip)
    }

    @Test("Automat rusza po upływie odstępu")
    func automaticRunsAfterInterval() {
        let old = Self.now.addingTimeInterval(-HealthSyncPlan.autoSyncInterval - 1)

        #expect(
            HealthSyncPlan.next(lastSyncedAt: old, now: Self.now, automatic: true)
                == .sync(days: HealthSyncPlan.incrementalDays)
        )
    }

    /// Kliknięcie „Synchronizuj teraz" ma zadziałać zawsze. Odstęp jest po to,
    /// żeby apka nie męczyła HealthKitu sama z siebie, a nie żeby ignorować
    /// użytkownika.
    @Test("Ręczne kliknięcie ignoruje odstęp")
    func manualIgnoresInterval() {
        let justNow = Self.now.addingTimeInterval(-5)

        #expect(
            HealthSyncPlan.next(lastSyncedAt: justNow, now: Self.now, automatic: false)
                == .sync(days: HealthSyncPlan.incrementalDays)
        )
    }

    @Test("Dokładnie na granicy odstępu automat już rusza")
    func boundaryRuns() {
        let exactly = Self.now.addingTimeInterval(-HealthSyncPlan.autoSyncInterval)

        #expect(
            HealthSyncPlan.next(lastSyncedAt: exactly, now: Self.now, automatic: true)
                == .sync(days: HealthSyncPlan.incrementalDays)
        )
    }

    /// Zegar potrafi cofnąć się przy zmianie strefy albo korekcie czasu.
    /// Ujemny odstęp nie może zablokować synchronizacji na zawsze.
    @Test("Znacznik z przyszłości nie blokuje na stałe")
    func toleratesClockSkew() {
        let future = Self.now.addingTimeInterval(HealthSyncPlan.autoSyncInterval * 5)
        let plan = HealthSyncPlan.next(lastSyncedAt: future, now: Self.now, automatic: true)

        // Przy cofniętym zegarze automat odpuści, ale ręczny przycisk zadziała —
        // i to on jest wyjściem awaryjnym.
        #expect(plan == .skip)
        #expect(
            HealthSyncPlan.next(lastSyncedAt: future, now: Self.now, automatic: false)
                == .sync(days: HealthSyncPlan.incrementalDays)
        )
    }

    /// Backfill celowo przekracza limit jednego żądania — ma sięgnąć całej
    /// historii z HealthKit, a nie zmieścić się w jednym POST. Stąd paczkowanie.
    @Test("Backfill sięga lat i nie mieści się w jednym żądaniu")
    func backfillIsDeep() {
        #expect(HealthSyncPlan.backfillDays > HealthSyncPlan.incrementalDays)
        #expect(HealthSyncPlan.backfillDays > HealthSyncPlan.daysPerRequest)
    }
}
