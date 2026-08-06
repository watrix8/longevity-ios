import SwiftUI

/// Pasek ostatnich 14 dni: spokojna linia średniej kroczącej (pine)
/// i skaczące punkty dziennych wyników (ochre) — układ z makiety.
struct TrendStrip: View {
    let points: [DayPoint]

    private let padX: CGFloat = 10
    private let topPad: CGFloat = 16
    private let botPad: CGFloat = 26

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }

            let values = points.flatMap { [$0.total, $0.baseline] }
            let rawLo = values.min() ?? 0
            let rawHi = values.max() ?? 100
            // Margines, żeby skrajne punkty nie kleiły się do krawędzi.
            let pad = max(6, (rawHi - rawLo) * 0.15)
            let lo = max(0, rawLo - pad)
            let hi = min(100, rawHi + pad)
            let span = max(1, hi - lo)

            let innerW = size.width - padX * 2
            let innerH = size.height - topPad - botPad
            let step = innerW / CGFloat(points.count - 1)

            func x(_ i: Int) -> CGFloat { padX + CGFloat(i) * step }
            func y(_ v: Double) -> CGFloat {
                topPad + (1 - CGFloat((v - lo) / span)) * innerH
            }

            // linia bazowa
            var baseline = Path()
            for (i, p) in points.enumerated() {
                let pt = CGPoint(x: x(i), y: y(p.baseline))
                if i == 0 { baseline.move(to: pt) } else { baseline.addLine(to: pt) }
            }
            context.stroke(
                baseline,
                with: .color(Palette.pine),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            )

            let selected = points.count - 1

            // łodyżki + punkty
            for (i, p) in points.enumerated() {
                let cx = x(i)
                var stem = Path()
                stem.move(to: CGPoint(x: cx, y: y(p.baseline)))
                stem.addLine(to: CGPoint(x: cx, y: y(p.total)))
                context.stroke(stem, with: .color(Palette.stem), lineWidth: 1.4)

                let cy = y(p.total)
                let isSelected = i == selected
                let r: CGFloat = isSelected ? 6 : 3.4

                if isSelected {
                    context.fill(
                        Path(ellipseIn: CGRect(x: cx - 10, y: cy - 10, width: 20, height: 20)),
                        with: .color(Palette.ochre.opacity(0.14))
                    )
                }

                let dot = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(Palette.ochre))

                if isSelected {
                    context.stroke(dot, with: .color(Palette.card), lineWidth: 1.6)
                    context.draw(
                        Text("\(Int(p.total))")
                            .font(AtlasFont.mono(11, .bold))
                            .foregroundStyle(Palette.ochreInk),
                        at: CGPoint(x: cx, y: cy - 15),
                        anchor: .center
                    )
                }
            }

            // podpisy: początek zakresu + trzy ostatnie dni
            let baseY = size.height - 6
            context.draw(
                tick("\(points.count) dni temu"),
                at: CGPoint(x: 2, y: baseY),
                anchor: .bottomLeading
            )
            for i in max(0, points.count - 3)..<points.count {
                context.draw(
                    tick(Self.weekday(points[i].date)),
                    at: CGPoint(x: x(i), y: baseY),
                    anchor: .bottom
                )
            }
        }
        .frame(height: 104)
    }

    private func tick(_ s: String) -> Text {
        Text(s)
            .font(AtlasFont.mono(9.5))
            .foregroundStyle(Palette.tick)
    }

    private static func weekday(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return "" }

        let out = DateFormatter()
        out.locale = Locale(identifier: "pl_PL")
        out.dateFormat = "EE"
        return out.string(from: date).capitalized
    }
}

/// Mała linia trendu w karcie podstawy.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let span = max(1, hi - lo)
            let step = size.width / CGFloat(values.count - 1)

            var path = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(
                    x: CGFloat(i) * step,
                    y: (1 - CGFloat((v - lo) / span)) * (size.height - 4) + 2
                )
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(
                path,
                with: .color(Palette.pine),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 34)
    }
}
