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
                periodStepper

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
                case .loaded(let groups):
                    ForEach(groups) { group in
                        // Nagłówek niesie komponent i wagę, więc kafelki nie
                        // powtarzają tego u siebie.
                        Kicker(verbatim: group.header, color: groupColor(group))
                            .padding(.top, group.id == "total" ? 0 : 8)
                        ForEach(group.metrics) { MetricCardView(metric: $0) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.card)
        .statusBarCover()
        .refreshable { await model.load() }
        .onAppear { Task { await model.refresh() } }
    }

    /// Sekcje wchodzące do wyniku wyróżnione kolorem — „Poza wynikiem"
    /// zostaje szare, żeby nie konkurowało wzrokowo z komponentami.
    private func groupColor(_ group: MetricGroup) -> Color {
        group.weight == nil ? Palette.tick : Palette.pine
    }

    /// Przesuwanie okna w przeszłość. Samą szerokość okna wybiera pigułka
    /// przy tytule — tu zostaje to, co zmienia się przy każdym tapnięciu.
    private var periodStepper: some View {
        HStack {
            stepButton("chevron.left", enabled: true) { model.shift(by: 1) }
            Spacer()
            Text(model.periodLabel)
                .font(AtlasFont.mono(11))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Spacer()
            stepButton("chevron.right", enabled: model.canGoForward) { model.shift(by: -1) }
        }
    }

    private func stepButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Task { await model.load() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Palette.pine : Palette.tick)
                .frame(width: 34, height: 28)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ScreenTitle(text: "Trendy")
                Spacer()
                windowPill
            }
            Text("W tym samym podziale co rozbicie na dashboardzie.\nStrzałkami cofasz się w czasie, przeciągnięciem odczytujesz dzień.")
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.muted)
        }
        .padding(.bottom, 4)
    }

    /// Szerokość okna siedzi tam, gdzie na Dashboardzie data — ten sam róg
    /// i ta sama pigułka. Segmentowany kontroler zabierał na to cały wiersz,
    /// choć wybór pada raz i zostaje na długo.
    private var windowPill: some View {
        Menu {
            Picker("Okno", selection: $model.window) {
                ForEach(TrendWindow.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.window.label)
                    .font(AtlasFont.mono(11))
                    .foregroundStyle(Palette.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.tick)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Palette.panel, in: Capsule())
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        }
        .onChange(of: model.window) { Task { await model.load() } }
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
                Text(metric.title)
                    .font(AtlasFont.display(16, .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                // Data zastępuje licznik punktów dopiero po dotknięciu wykresu —
                // bez niej nie wiadomo, czy wielka liczba to dziś, czy 12 lipca.
                if selection != nil, let shown {
                    Text(metric.pointLabel(shown.date))
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
                    Text(metric.points.first.map { metric.axisLabel($0.date) } ?? "")
                    Spacer()
                    Text(metric.points.last.map { metric.axisLabel($0.date) } ?? "")
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
                Text("Śr. 7 dni: \(metric.avg7.map(Self.format) ?? "—")\(unitSuffix)")
                Text("Śr. okna: \(metric.avgAll.map(Self.format) ?? "—")\(unitSuffix)")
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
                // Podniesienie palca kasuje wybór: karta wraca do ostatniego
                // pomiaru, a linia znika. Zostawiona kreska sugerowałaby, że
                // wykres jest w jakimś trybie, z którego trzeba wyjść.
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.15)) { selection = nil }
                }
        )
        // Haptyk tylko przy wskazywaniu dnia — przy zwalnianiu byłby drugim,
        // niepotrzebnym sygnałem tuż po ostatnim.
        .sensoryFeedback(trigger: selection) { _, new in
            new == nil ? nil : .selection
        }
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
                    id: "sleep_hours", title: String(localized: "Sen"), unit: "h", positiveHigher: true,
                    role: .feeds(component: ScoreComponents.label(forComponent: "sleep"), weight: 0.30), points: points
                )
            )
            MetricCardView(
                metric: Metric(
                    id: "resting_hr", title: String(localized: "Tętno spoczynkowe"), unit: "bpm",
                    positiveHigher: false,
                    role: .feeds(component: ScoreComponents.label(forComponent: "regeneration"), weight: 0.15),
                    points: points.map { SeriesPoint(date: $0.date, value: $0.value * 6.4) }
                )
            )
        }
        .padding(20)
    }
    .background(Palette.card)
}
