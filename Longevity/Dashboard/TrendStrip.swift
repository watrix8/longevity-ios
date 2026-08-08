import SwiftUI

/// Geometria paska — jedno źródło prawdy dla rysowania i dla trafiania palcem,
/// dokładnie jak `ChartGeometry` w Trendach. Osobny typ, bo reguła skali jest
/// tu inna: tam dół przykleja się do zera (parytet z webem), tu okno jeździ
/// za danymi.
struct StripGeometry: Equatable {
    /// Najmniejsza rozpiętość osi Y. Bez niej autoskalowanie rozciąga różnicę
    /// 90→91 na całą wysokość i mała zmiana wygląda jak skok formy.
    static let minSpan: Double = 20

    static let padX: CGFloat = 12
    static let padTop: CGFloat = 24
    static let padBottom: CGFloat = 22

    let count: Int

    private let size: CGSize
    private let lo: Double
    private let span: Double
    private let step: CGFloat

    init(values: [Double], size: CGSize) {
        self.size = size
        count = values.count

        let rawLo = values.min() ?? 0
        let rawHi = values.max() ?? 100
        let mid = (rawLo + rawHi) / 2
        let needed = max(Self.minSpan, (rawHi - rawLo) * 1.35)

        // Okno wyśrodkowane na danych i docięte do 0...100 — przy wyniku 96
        // nie ma po co rysować pustego pasa nad skalą.
        var low = mid - needed / 2
        var high = mid + needed / 2
        if high > 100 {
            low -= high - 100
            high = 100
        }
        if low < 0 {
            high = min(100, high - low)
            low = 0
        }

        lo = low
        span = max(1, high - low)
        step = count > 1 ? (size.width - Self.padX * 2) / CGFloat(count - 1) : 0
    }

    func x(_ index: Int) -> CGFloat { Self.padX + CGFloat(index) * step }

    func y(_ value: Double) -> CGFloat {
        let inner = size.height - Self.padTop - Self.padBottom
        return Self.padTop + (1 - CGFloat((value - lo) / span)) * inner
    }

    /// Punkt NAJBLIŻSZY, a nie ten po lewej — pod palcem ma się zaznaczyć to,
    /// co widać pod palcem.
    func index(atX x: CGFloat) -> Int {
        guard count > 1, step > 0 else { return 0 }
        return min(max(Int(((x - Self.padX) / step).rounded()), 0), count - 1)
    }
}

/// Główny wykres dashboardu: spokojna linia trendu (pine) i skaczące punkty
/// dziennych wyników (ochre). Przeciągnięcie po nim wybiera dzień.
struct TrendStrip: View {
    let points: [DayPoint]
    @Binding var selection: Int?

    @State private var size: CGSize = .zero

    /// Do skali wchodzą i wyniki, i trend — inaczej linia potrafi wyjechać
    /// poza kadr w dniu z mocnym odchyleniem.
    private var values: [Double] {
        points.compactMap(\.total) + points.compactMap(\.trend)
    }

    /// Domyślnie ostatni dzień Z POMIAREM, a nie ostatni slot: przy dziurze
    /// na końcu wielka liczba nie miałaby czego pokazać.
    private var shownIndex: Int? {
        if let selection, points.indices.contains(selection) { return selection }
        return points.lastIndex { $0.total != nil }
    }

    var body: some View {
        Canvas { context, canvasSize in
            guard points.count > 1 else { return }
            let g = StripGeometry(values: values, size: canvasSize)

            drawSelectionRule(context, g, canvasSize)
            drawTrendLine(context, g)
            drawLoneTrendMarks(context, g)
            drawStems(context, g)
            drawDots(context, g)
            drawTrendLabel(context, g, width: canvasSize.width)
            drawAxis(context, size: canvasSize)
        }
        .frame(height: 150)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        // `minimumDistance` większe od zera oddaje pionowe przeciągnięcie
        // ScrollView-owi — przy zerze wykres łapałby każdy dotyk i ekran
        // przestawałby się przewijać nad kartą.
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag in
                    selection = StripGeometry(values: values, size: size)
                        .index(atX: drag.location.x)
                }
                // Podniesienie palca kasuje wybór: wykres wraca do dziś,
                // zamiast zostawać w trybie, z którego trzeba wychodzić.
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.15)) { selection = nil }
                }
        )
        .sensoryFeedback(trigger: selection) { _, new in
            new == nil ? nil : .selection
        }
        .accessibilityLabel("Wykres ostatnich \(points.count) dni")
    }

    // MARK: - Warstwy

    private func drawSelectionRule(_ context: GraphicsContext, _ g: StripGeometry, _ size: CGSize) {
        guard let selection, points.indices.contains(selection) else { return }
        var rule = Path()
        rule.move(to: CGPoint(x: g.x(selection), y: StripGeometry.padTop - 6))
        rule.addLine(to: CGPoint(x: g.x(selection), y: size.height - StripGeometry.padBottom + 4))
        context.stroke(rule, with: .color(Palette.tick), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    /// Linia trendu zaczyna się dopiero tam, gdzie trend istnieje — w pierwszym
    /// dniu szeregu nie ma go z czego policzyć.
    private func drawTrendLine(_ context: GraphicsContext, _ g: StripGeometry) {
        var line = Path()
        var started = false
        for (i, p) in points.enumerated() {
            // Brak trendu przerywa linię zamiast ją przeciągać nad dziurą —
            // domknięty odcinek sugerowałby ciągłość, której nie ma.
            guard let trend = p.trend else {
                started = false
                continue
            }
            let pt = CGPoint(x: g.x(i), y: g.y(trend))
            if started { line.addLine(to: pt) } else { line.move(to: pt); started = true }
        }
        context.stroke(
            line,
            with: .color(Palette.pine),
            style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
        )
    }

    /// Trend bez sąsiada nie narysuje się jako linia — zostaje po nim krótka
    /// kreska. Bez niej podpis „trend 66" wisiał w powietrzu, bo dzień po
    /// przerwie bywa jedynym, który ma pełne okno.
    private func drawLoneTrendMarks(_ context: GraphicsContext, _ g: StripGeometry) {
        for (i, p) in points.enumerated() {
            guard let trend = p.trend else { continue }
            let hasNeighbour = (i > 0 && points[i - 1].trend != nil)
                || (i + 1 < points.count && points[i + 1].trend != nil)
            guard !hasNeighbour else { continue }

            var dash = Path()
            dash.move(to: CGPoint(x: g.x(i) - 7, y: g.y(trend)))
            dash.addLine(to: CGPoint(x: g.x(i) + 7, y: g.y(trend)))
            context.stroke(
                dash,
                with: .color(Palette.pine),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
            )
        }
    }

    private func drawStems(_ context: GraphicsContext, _ g: StripGeometry) {
        for (i, p) in points.enumerated() {
            guard let trend = p.trend, let total = p.total else { continue }
            var stem = Path()
            stem.move(to: CGPoint(x: g.x(i), y: g.y(trend)))
            stem.addLine(to: CGPoint(x: g.x(i), y: g.y(total)))
            context.stroke(stem, with: .color(Palette.stem), lineWidth: 1.4)
        }
    }

    /// Dzień bez pomiaru nie dostaje kropki — puste miejsce mówi wprost,
    /// że tego dnia nic nie zmierzono.
    private func drawDots(_ context: GraphicsContext, _ g: StripGeometry) {
        for (i, p) in points.enumerated() {
            guard let total = p.total else { continue }
            let center = CGPoint(x: g.x(i), y: g.y(total))
            let isShown = i == shownIndex
            let r: CGFloat = isShown ? 6 : 3.4

            if isShown {
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)),
                    with: .color(Palette.ochre.opacity(0.14))
                )
            }

            let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.fill(dot, with: .color(Palette.ochre))

            if isShown {
                // Obwódka w kolorze tła odcina kropkę od łodyżki pod nią.
                context.stroke(dot, with: .color(Palette.card), lineWidth: 1.6)
                context.draw(
                    Text(verbatim: "\(Int(total))")
                        .font(AtlasFont.mono(11, .bold))
                        .foregroundStyle(Palette.ochreInk),
                    at: CGPoint(x: center.x, y: center.y - 15),
                    anchor: .center
                )
            }
        }
    }

    /// Wartość trendu podpisana na końcu linii — to ona zastąpiła osobną kartę
    /// „Podstawa”. Podpis ląduje po przeciwnej stronie linii niż ostatnia
    /// kropka, żeby się z nią nie zlepiał.
    private func drawTrendLabel(_ context: GraphicsContext, _ g: StripGeometry, width: CGFloat) {
        guard let last = points.last, let trend = last.trend else { return }
        // Bez pomiaru w ostatnim dniu nie ma z czym kolidować, więc podpis
        // idzie pod linię — tak samo jak przy wyniku powyżej trendu.
        let below = (last.total ?? trend) >= trend
        context.draw(
            Text("trend \(Int(trend.rounded()))")
                .font(AtlasFont.mono(9.5, .bold))
                .foregroundStyle(Palette.pine),
            at: CGPoint(x: width - 2, y: g.y(trend) + (below ? 8 : -8)),
            anchor: below ? .topTrailing : .bottomTrailing
        )
    }

    /// Podpisy tylko w rogach. Poprzednia wersja rysowała etykietę zakresu
    /// w x=2 i tick dnia w x=10 — przy krótkim szeregu nachodziły na siebie.
    private func drawAxis(_ context: GraphicsContext, size: CGSize) {
        let baseY = size.height - 4
        if let first = points.first {
            context.draw(tick(Self.shortDay(first.date)), at: CGPoint(x: 2, y: baseY), anchor: .bottomLeading)
        }
        context.draw(
            tick(String(localized: "dziś")),
            at: CGPoint(x: size.width - 2, y: baseY),
            anchor: .bottomTrailing
        )
    }

    /// Wprost `verbatim` — pod spodem lecą sformatowane daty, nie klucze.
    private func tick(_ s: String) -> Text {
        Text(verbatim: s)
            .font(AtlasFont.mono(9.5))
            .foregroundStyle(Palette.tick)
    }

    /// "2026-07-25" → "25 lip". `FormatStyle` zamiast `DateFormatter`, bo ten
    /// drugi nie jest `Sendable`. Południe chroni przed przeskokiem o strefę.
    static func shortDay(_ iso: String) -> String {
        guard let date = try? Date("\(iso)T12:00:00Z", strategy: .iso8601) else { return iso }
        return date.formatted(
            .dateTime.locale(Locale.autoupdatingCurrent).day().month(.abbreviated)
        )
    }

    /// "2026-08-06" → "6 sierpnia" — nagłówek karty w trakcie przeciągania.
    static func longDay(_ iso: String) -> String {
        guard let date = try? Date("\(iso)T12:00:00Z", strategy: .iso8601) else { return iso }
        return date.formatted(
            .dateTime.locale(Locale.autoupdatingCurrent).day().month(.wide)
        )
    }
}
