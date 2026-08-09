import Foundation
import Testing

@testable import Longevity

@Suite("Geometria paska na dashboardzie")
struct StripGeometryTests {
    /// Szerokość dobrana tak, żeby krok wyszedł równo (24 na marginesy,
    /// 260 na trzynaście odstępów) — porównania mogą być dokładne.
    private let size = CGSize(width: 284, height: 150)
    private let days = 14

    /// Komplet: każdy dzień ma wynik i wartość trendu, więc wartości jest
    /// dwa razy tyle, co dni.
    private var fullValues: [Double] { Array(repeating: 80.0, count: days * 2) }

    /// Sedno regresji: oś X liczy DNI, a nie wartości. Krok brany z wartości
    /// był o połowę za mały i szereg kończył się w połowie karty, choć oś
    /// podpisywała „dziś" przy prawej krawędzi.
    @Test("Ostatni dzień stoi przy prawej krawędzi, nie w połowie")
    func lastDayReachesTrailingEdge() {
        let g = StripGeometry(days: days, values: fullValues, size: size)

        #expect(g.x(0) == StripGeometry.padX)
        #expect(g.x(days - 1) == size.width - StripGeometry.padX)
    }

    /// `values` gubi dni bez pomiaru (`compactMap`), więc dziura w danych
    /// przesuwała wszystkie kropki. Okno 14 dni ma się rysować tak samo
    /// niezależnie od tego, ile z nich ma pomiar.
    @Test("Dziura w danych nie zmienia rozstawu dni")
    func spacingIgnoresGaps() {
        let full = StripGeometry(days: days, values: fullValues, size: size)
        let holes = StripGeometry(days: days, values: [80, 82, 79], size: size)

        #expect(full.x(7) == holes.x(7))
        #expect(holes.x(days - 1) == size.width - StripGeometry.padX)
    }

    /// Palec na prawej połowie wykresu dawał indeks spoza `points`, więc
    /// zaznaczenie po cichu nie działało — tam po prostu nie było czego wybrać.
    @Test("Przeciąganie trafia w dzień na całej szerokości")
    func dragCoversWholeWidth() {
        let g = StripGeometry(days: days, values: fullValues, size: size)

        #expect(g.index(atX: g.x(0)) == 0)
        #expect(g.index(atX: g.x(days - 1)) == days - 1)
        #expect(g.index(atX: g.x(9)) == 9)
        // Najbliższy dzień, nie ten po lewej.
        #expect(g.index(atX: g.x(6) + 11) == 7)
    }

    @Test("Palec poza płótnem zostaje przy skrajnym dniu")
    func dragClampsToRange() {
        let g = StripGeometry(days: days, values: fullValues, size: size)

        #expect(g.index(atX: -80) == 0)
        #expect(g.index(atX: size.width + 80) == days - 1)
    }

    @Test("Jeden dzień nie dzieli przez zero")
    func singleDayHasNoStep() {
        let g = StripGeometry(days: 1, values: [80], size: size)

        #expect(g.x(0) == StripGeometry.padX)
        #expect(g.index(atX: 200) == 0)
    }

    /// Druga połowa podziału: wartości dalej opisują skalę pionową — i wyniki,
    /// i trend, żeby linia nie wyjechała poza kadr.
    @Test("Skala pionowa idzie z wartości, z zapasem na małe różnice")
    func verticalScaleComesFromValues() {
        // Jedna wartość: rozpiętość schodzi do minimum, więc 80 ląduje
        // w połowie wysokości zamiast przykleić się do krawędzi.
        let flat = StripGeometry(days: days, values: [80], size: size)
        let inner = size.height - StripGeometry.padTop - StripGeometry.padBottom

        #expect(abs(flat.y(80) - (StripGeometry.padTop + inner / 2)) < 0.001)
        #expect(abs(flat.y(80 + StripGeometry.minSpan / 2) - StripGeometry.padTop) < 0.001)

        // Trend poza zakresem wyników mieści się w kadrze — po to wchodzi
        // do skali razem z nimi.
        let wide = StripGeometry(days: days, values: [95, 60], size: size)

        #expect(wide.y(95) > StripGeometry.padTop)
        #expect(wide.y(60) < size.height - StripGeometry.padBottom)
    }
}
