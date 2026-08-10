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
                        ForEach(group.metrics) { MetricCardView(metric: $0, span: model.visibleSpan) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.paper)
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
                // Biel, nie `panel` — przycisk stoi wprost na tle strony.
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var header: some View {
        HStack {
            ScreenTitle(text: "Trendy")
            Spacer()
            windowPill
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
            .background(Palette.card, in: Capsule())
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        }
        .onChange(of: model.window) { Task { await model.load() } }
    }
}

struct MetricCardView: View {
    let metric: Metric
    /// Okno, w którym karta rysuje szereg — wspólne dla wszystkich kart,
    /// żeby ta sama data wypadała na tej samej pionowej linii.
    let span: DaySpan

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
                Text(shown.map { metric.text($0.value) } ?? "—")
                    .font(AtlasFont.display(34))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // Placeholder nie może krzyczeć kolorem akcentu — w 34 pt
                    // ochrowy myślnik wygląda jak pasek danych.
                    .foregroundStyle(shown == nil ? Palette.muted : Palette.ochre)
                // Metryki z jednostką w samej wartości (sen: „8h 40min") mają
                // ją pustą — pusty `Text` zabrałby tu tylko odstęp.
                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(AtlasFont.body(12))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                // Mono, nie body: Hanken nie ma w cmapie ↗ ani ↘, więc iOS
                // podmieniłby je po cichu na krój systemowy i jedyny glif
                // z obcej rodziny siedziałby tuż przy wielkiej liczbie.
                // Space Mono ma wszystkie trzy strzałki.
                Text(metric.arrow(at: shownIndex))
                    .font(AtlasFont.mono(18))
                    .foregroundStyle(Palette.pine)
            }
            .padding(.top, 8)
            .animation(.easeOut(duration: 0.12), value: shownIndex)

            if metric.points.count > 1 {
                MetricChart(points: metric.points, span: span, selection: $selection)
                    .padding(.top, 10)

                // Podpisy to granice OKNA, nie pierwszy i ostatni pomiar —
                // oś idzie teraz po kalendarzu, więc kończy się tam, gdzie okno.
                HStack {
                    Text(metric.axisLabel(span.from))
                    Spacer()
                    Text(metric.axisLabel(span.to))
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

            // Jedna średnia, z całego widocznego okna. „Śr. 7 dni" obok niej
            // zmuszała do porównywania dwóch liczb, których karta i tak nie
            // zestawiała ze sobą — od porównania jest strzałka i wykres.
            Text("Średnia: \(metric.avgAll.map(metric.text) ?? "—")\(unitSuffix)")
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

}

/// Geometria wykresu — jedno źródło prawdy dla rysowania linii i dla trafiania
/// w punkt palcem.
///
/// To nie jest nadmiarowa abstrakcja: gdyby obie te rzeczy liczyły pozycję
/// osobno, wystarczyłaby inna kolejność zaokrągleń, żeby marker stanął obok
/// linii zamiast na niej.
struct ChartGeometry: Equatable {
    /// Margines na grubość kreski i promień kropki. Bez niego punkt z pierwszego
    /// albo ostatniego dnia stoi dokładnie na krawędzi płótna i połowa kropki
    /// (a przy skrajnych wartościach też kawałek linii) zostaje ucięta.
    static let inset: CGFloat = 8

    let size: CGSize
    let count: Int

    private let lo: Double
    private let valueSpan: Double
    private let span: DaySpan
    private let points: [SeriesPoint]

    init(points: [SeriesPoint], span: DaySpan, size: CGSize) {
        self.points = points
        self.span = span
        self.size = size
        count = points.count

        // Okno wyśrodkowane na danych, nie przyklejone do zera. Przy zerze
        // szereg 89, 90, 89 lądował cienkim paskiem przy górnej krawędzi,
        // a cała reszta pola stała pusta. Minimalna rozpiętość jest liczona
        // od skali metryki — bez niej płaski szereg rozciągnąłby się na całą
        // wysokość i wyglądał jak huśtawka.
        let values = points.map(\.value)
        let rawLo = values.min() ?? 0
        let rawHi = values.max() ?? 1
        let minSpan = max(abs(rawHi) * 0.08, 0.001)
        let needed = max(minSpan, (rawHi - rawLo) * 1.35)

        lo = (rawLo + rawHi) / 2 - needed / 2
        valueSpan = needed
    }

    /// Pozioma pozycja wynika z DATY, nie z numeru pomiaru. Przy przerwie
    /// w noszeniu zegarka wykres zostawia w tym miejscu odstęp, zamiast
    /// ściskać czas i udawać, że pomiary szły dzień po dniu.
    func point(at index: Int) -> CGPoint {
        guard points.indices.contains(index) else { return .zero }
        let point = points[index]
        let width = max(1, size.width - Self.inset * 2)
        let height = max(1, size.height - Self.inset * 2)
        return CGPoint(
            x: Self.inset + CGFloat(span.fraction(of: point.date)) * width,
            y: Self.inset + (1 - CGFloat((point.value - lo) / valueSpan)) * height
        )
    }

    /// Punkt NAJBLIŻSZY, a nie ten po lewej — pod palcem ma się zaznaczyć to,
    /// co widać pod palcem. Odległość mierzona po osi czasu, bo przy nierównych
    /// odstępach dzielenie przez stały krok wskazywało nie ten dzień.
    func index(atX x: CGFloat) -> Int {
        guard count > 1, size.width > 0 else { return 0 }
        let width = max(1, size.width - Self.inset * 2)
        let target = min(max(Double((x - Self.inset) / width), 0), 1)

        return points.indices.min { left, right in
            abs(span.fraction(of: points[left].date) - target)
                < abs(span.fraction(of: points[right].date) - target)
        } ?? 0
    }
}

/// Linia 30 dni. Przeciągnięcie po niej wybiera dzień, który karta pokazuje
/// wielką liczbą.
struct MetricChart: View {
    let points: [SeriesPoint]
    let span: DaySpan
    @Binding var selection: Int?

    @State private var size: CGSize = .zero

    /// Przy pomiarach rzadszych niż co drugi dzień sama linia nie mówi, gdzie
    /// są prawdziwe odczyty — dostają wtedy kropki. Przy szeregu codziennym
    /// byłoby ich tyle, że zlałyby się w pasek.
    private var showsDots: Bool { points.count * 2 <= span.days }

    var body: some View {
        Canvas { context, canvasSize in
            guard points.count > 1 else { return }
            let geometry = ChartGeometry(points: points, span: span, size: canvasSize)

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

            if showsDots {
                for index in points.indices {
                    let point = geometry.point(at: index)
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
                        with: .color(Palette.pine)
                    )
                }
            }

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
                    let geometry = ChartGeometry(points: points, span: span, size: size)
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
        // Tło wraca, ale ciaśniej: wcześniej wykres siedział w środku bloku
        // z własnym marginesem, więc dane zajmowały ledwie połowę zieleni.
        // Teraz blok to dokładnie płótno, a jedyny odstęp to margines na
        // grubość kreski, bez którego kropka wychodzi obcięta.
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
            // Okno szersze niż sam szereg — podgląd ma pokazywać, że pomiary
            // kończą się przed prawą krawędzią, a nie dobijają do niej zawsze.
            let span = DaySpan(from: "2026-07-10", to: "2026-08-08")

            MetricCardView(
                metric: Metric(
                    id: "sleep_hours", title: String(localized: "Sen"), unit: "", positiveHigher: true,
                    role: .feeds(component: ScoreComponents.label(forComponent: "sleep"), weight: 0.33),
                    format: .duration, points: points
                ),
                span: span
            )
            MetricCardView(
                metric: Metric(
                    id: "resting_hr", title: String(localized: "Tętno spoczynkowe"), unit: "bpm",
                    positiveHigher: false,
                    role: .feeds(component: ScoreComponents.label(forComponent: "regeneration"), weight: 0.17),
                    points: points.map { SeriesPoint(date: $0.date, value: $0.value * 6.4) }
                ),
                span: span
            )
        }
        .padding(20)
    }
    .background(Palette.card)
}
