import SwiftUI

struct TrendsView: View {
    @State private var model: TrendsViewModel

    init(model: TrendsViewModel = TrendsViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                switch model.state {
                case .loading:
                    ProgressView()
                        .tint(Palette.pine)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                case .failed(let message):
                    VStack(spacing: 10) {
                        Text("Nie udało się wczytać trendów")
                            .font(AtlasFont.display(18))
                            .foregroundStyle(Palette.ink)
                        Text(message)
                            .font(AtlasFont.body(13))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                        Button("Spróbuj ponownie") { Task { await model.load() } }
                            .font(AtlasFont.body(13, .semibold))
                            .tint(Palette.pine)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                case .loaded(let metrics):
                    ForEach(metrics) { MetricCardView(metric: $0) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.card)
        .refreshable { await model.load() }
        .task {
            if case .loading = model.state { await model.load() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trendy")
                .font(AtlasFont.display(28, .heavy))
                .foregroundStyle(Palette.ink)
            Text("Ostatnie 30 dni. Przeciągnij po wykresie, żeby odczytać dzień.")
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.muted)
        }
        .padding(.bottom, 4)
    }
}

struct MetricCardView: View {
    let metric: Metric

    /// Dzień wskazany palcem. `nil` = karta pokazuje ostatni pomiar.
    @State private var selection: Int?

    /// Zawężenie do istniejącego indeksu, bo `selection` przeżywa odświeżenie
    /// danych — a po nim szereg bywa krótszy niż przy poprzednim wczytaniu.
    private var shownIndex: Int? {
        if let selection, metric.points.indices.contains(selection) { return selection }
        return metric.points.indices.last
    }

    private var shown: SeriesPoint? { shownIndex.map { metric.points[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title)
                        .font(AtlasFont.display(16, .semibold))
                        .foregroundStyle(Palette.ink)
                    // Bez tej etykiety kafelek kroków wygląda tak samo ważnie
                    // jak sen, który odpowiada za 30% wyniku.
                    Text(metric.role.badge)
                        .font(AtlasFont.mono(9))
                        .foregroundStyle(metric.role.countsToScore ? Palette.pine : Palette.tick)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            metric.role.countsToScore ? Palette.pineSoft : Palette.panel,
                            in: Capsule()
                        )
                }
                Spacer()
                // Data zastępuje licznik punktów dopiero po dotknięciu wykresu —
                // bez niej nie wiadomo, czy wielka liczba to dziś, czy 12 lipca.
                if selection != nil, let shown {
                    Text(Self.polishDay(shown.date))
                        .font(AtlasFont.mono(10.5))
                        .foregroundStyle(Palette.ochreInk)
                } else {
                    Text("\(metric.points.count) pkt")
                        .font(AtlasFont.mono(10.5))
                        .foregroundStyle(Palette.muted)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(shown.map { Self.format($0.value) } ?? "—")
                    .font(AtlasFont.display(34))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // Placeholder nie może krzyczeć kolorem akcentu — w 34 pt
                    // ochrowy myślnik wygląda jak pasek danych.
                    .foregroundStyle(shown == nil ? Palette.muted : Palette.ochre)
                Text(metric.unit)
                    .font(AtlasFont.body(12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text(metric.arrow(at: shownIndex))
                    .font(AtlasFont.body(20))
                    .foregroundStyle(Palette.pine)
            }
            .padding(.top, 8)
            .animation(.easeOut(duration: 0.12), value: shownIndex)

            if metric.points.count > 1 {
                MetricChart(points: metric.points, selection: $selection)
                    .padding(.top, 10)

                HStack {
                    Text(String(metric.points.first?.date.suffix(5) ?? ""))
                    Spacer()
                    Text(String(metric.points.last?.date.suffix(5) ?? ""))
                }
                .font(AtlasFont.mono(9.5))
                .foregroundStyle(Palette.tick)
                .padding(.top, 4)
            } else {
                Text("Za mało danych na trend.")
                    .font(AtlasFont.body(12))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 8)
            }

            HStack(spacing: 16) {
                Text("Śr. 7d: \(metric.avg7.map(Self.format) ?? "—")\(unitSuffix)")
                Text("Śr. 30d: \(metric.avg30.map(Self.format) ?? "—")\(unitSuffix)")
            }
            .font(AtlasFont.body(12))
            .foregroundStyle(Palette.muted)
            .padding(.top, 12)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
    }

    private var unitSuffix: String { metric.unit.isEmpty ? "" : " \(metric.unit)" }

    /// Bez zbędnego ".0" na całkowitych wartościach.
    private static func format(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    /// "2026-08-06" → "6 sierpnia". `FormatStyle` zamiast `DateFormatter`,
    /// bo ten drugi nie jest `Sendable` i musiałby wisieć jako współdzielony stan.
    /// Południe w parsowanym znaczniku chroni przed przeskokiem daty o strefę.
    private static func polishDay(_ iso: String) -> String {
        guard let date = try? Date("\(iso)T12:00:00Z", strategy: .iso8601) else { return iso }
        return date.formatted(
            .dateTime.locale(Locale(identifier: "pl_PL")).day().month(.wide)
        )
    }
}

/// Geometria wykresu — jedno źródło prawdy dla rysowania linii i dla trafiania
/// w punkt palcem.
///
/// To nie jest nadmiarowa abstrakcja: gdyby obie te rzeczy liczyły pozycję
/// osobno, wystarczyłaby inna kolejność zaokrągleń, żeby marker stanął obok
/// linii zamiast na niej.
struct ChartGeometry: Equatable {
    let size: CGSize
    let count: Int

    private let lo: Double
    private let span: Double
    private let step: CGFloat
    private let values: [Double]

    init(values: [Double], size: CGSize) {
        self.values = values
        self.size = size
        count = values.count

        // Skala jak w webie: dół przyklejony do zera (albo minimum, gdy ujemne).
        lo = min(values.min() ?? 0, 0)
        let hi = max(values.max() ?? 1, 1)
        span = max(1, hi - lo)
        step = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
    }

    func point(at index: Int) -> CGPoint {
        guard values.indices.contains(index) else { return .zero }
        return CGPoint(
            x: CGFloat(index) * step,
            y: size.height - CGFloat((values[index] - lo) / span) * size.height
        )
    }

    /// Punkt NAJBLIŻSZY, a nie ten po lewej — pod palcem ma się zaznaczyć to,
    /// co widać pod palcem. Poza wykresem przywiera do skrajnego dnia.
    func index(atX x: CGFloat) -> Int {
        guard count > 1, step > 0 else { return 0 }
        return min(max(Int((x / step).rounded()), 0), count - 1)
    }
}

/// Linia 30 dni. Przeciągnięcie po niej wybiera dzień, który karta pokazuje
/// wielką liczbą.
struct MetricChart: View {
    let points: [SeriesPoint]
    @Binding var selection: Int?

    @State private var size: CGSize = .zero

    var body: some View {
        Canvas { context, canvasSize in
            guard points.count > 1 else { return }
            let geometry = ChartGeometry(values: points.map(\.value), size: canvasSize)

            var line = Path()
            for index in points.indices {
                let point = geometry.point(at: index)
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(
                line,
                with: .color(Palette.pine),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )

            if let selection, points.indices.contains(selection) {
                let point = geometry.point(at: selection)

                var rule = Path()
                rule.move(to: CGPoint(x: point.x, y: 0))
                rule.addLine(to: CGPoint(x: point.x, y: canvasSize.height))
                context.stroke(
                    rule,
                    with: .color(Palette.tick),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )

                // Obwódka w kolorze tła odcina kropkę od linii pod nią.
                let dot = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: dot), with: .color(Palette.ochre))
                context.stroke(Path(ellipseIn: dot), with: .color(Palette.panel), lineWidth: 2)
            } else if let last = points.indices.last {
                let point = geometry.point(at: last)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)),
                    with: .color(Palette.ochre)
                )
            }
        }
        .frame(height: 92)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        // `minimumDistance` większe od zera oddaje pionowe przeciągnięcie
        // ScrollView-owi. Przy zerze wykres łapałby każdy dotyk i lista
        // przestawałaby się przewijać nad kartą.
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag in
                    let geometry = ChartGeometry(values: points.map(\.value), size: size)
                    selection = geometry.index(atX: drag.location.x)
                }
        )
        .sensoryFeedback(.selection, trigger: selection)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview("Trendy") {
    TrendsView()
}

/// Karta z danymi — `TrendsView()` bez sesji pokazuje tylko spinner, a tu
/// chodzi o obejrzenie przeciągania po wykresie.
#Preview("Karta metryki") {
    let hours: [Double] = [
        7.2, 6.8, 8.1, 7.5, 5.9, 7.8, 8.3, 7.1, 6.5, 7.9,
        8.0, 7.4, 6.2, 7.7, 8.4, 7.0, 7.3, 6.9, 8.2, 7.6,
    ]
    let points = hours.enumerated().map { index, value in
        SeriesPoint(date: String(format: "2026-07-%02d", index + 18), value: value)
    }

    ScrollView {
        VStack(spacing: 14) {
            MetricCardView(
                metric: Metric(
                    id: "sleep_hours", title: "Sen", unit: "h", positiveHigher: true,
                    role: .feeds(component: "Sen", weight: 0.30), points: points
                )
            )
            MetricCardView(
                metric: Metric(
                    id: "resting_hr", title: "Tętno spoczynkowe", unit: "bpm",
                    positiveHigher: false,
                    role: .feeds(component: "Regeneracja", weight: 0.15),
                    points: points.map { SeriesPoint(date: $0.date, value: $0.value * 6.4) }
                )
            )
        }
        .padding(20)
    }
    .background(Palette.card)
}
