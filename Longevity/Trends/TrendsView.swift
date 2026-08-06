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
            Text("Ostatnie 30 dni — wszystkie wskaźniki w jednym miejscu.")
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.muted)
        }
        .padding(.bottom, 4)
    }
}

struct MetricCardView: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .font(AtlasFont.display(16, .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(metric.points.count) pkt")
                    .font(AtlasFont.mono(10.5))
                    .foregroundStyle(Palette.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.last.map(Self.format) ?? "—")
                    .font(AtlasFont.display(34))
                    .monospacedDigit()
                    // Placeholder nie może krzyczeć kolorem akcentu — w 34 pt
                    // ochrowy myślnik wygląda jak pasek danych.
                    .foregroundStyle(metric.last == nil ? Palette.muted : Palette.ochre)
                Text(metric.unit)
                    .font(AtlasFont.body(12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text(metric.arrow)
                    .font(AtlasFont.body(20))
                    .foregroundStyle(Palette.pine)
            }
            .padding(.top, 8)

            if metric.points.count > 1 {
                MetricChart(points: metric.points)
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
}

/// Linia 30 dni z zaznaczonym ostatnim punktem — odpowiednik SVG z weba.
struct MetricChart: View {
    let points: [SeriesPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let values = points.map(\.value)
            // Skala jak w webie: dół przyklejony do zera (albo minimum, gdy ujemne).
            let lo = min(values.min() ?? 0, 0)
            let hi = max(values.max() ?? 1, 1)
            let span = max(1, hi - lo)
            let step = size.width / CGFloat(points.count - 1)

            var path = Path()
            for (i, p) in points.enumerated() {
                let pt = CGPoint(
                    x: CGFloat(i) * step,
                    y: size.height - CGFloat((p.value - lo) / span) * size.height
                )
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(
                path,
                with: .color(Palette.pine),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )

            if let lastValue = values.last {
                let cx = CGFloat(points.count - 1) * step
                let cy = size.height - CGFloat((lastValue - lo) / span) * size.height
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - 3.5, y: cy - 3.5, width: 7, height: 7)),
                    with: .color(Palette.ochre)
                )
            }
        }
        .frame(height: 92)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    TrendsView()
}
