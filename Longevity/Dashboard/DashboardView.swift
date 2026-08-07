import SwiftUI

struct DashboardView: View {
    /// Rozwinięte komponenty rozbicia — id zamiast indeksu, bo lista zmienia
    /// długość razem z pokryciem danych.
    @State private var expanded: Set<String> = []

    @State private var model: DashboardViewModel

    init(model: DashboardViewModel = DashboardViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.state {
                case .loading:
                    placeholder { ProgressView().tint(Palette.pine) }
                case .empty:
                    placeholder {
                        VStack(spacing: 10) {
                            Text("Brak wyników")
                                .font(AtlasFont.display(20))
                                .foregroundStyle(Palette.ink)
                            Text("Zrób check-in na webie albo w Telegramie — wynik pojawi się tutaj.")
                                .font(AtlasFont.body(14))
                                .foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.center)
                        }
                    }
                case .failed(let message):
                    placeholder {
                        VStack(spacing: 10) {
                            Text("Nie udało się wczytać")
                                .font(AtlasFont.display(20))
                                .foregroundStyle(Palette.ink)
                            Text(message)
                                .font(AtlasFont.body(13))
                                .foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.center)
                            Button("Spróbuj ponownie") { Task { await model.load() } }
                                .font(AtlasFont.body(13, .semibold))
                                .tint(Palette.pine)
                        }
                    }
                case .loaded(let data):
                    content(data)
                }

                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.card)
        .refreshable { await model.load() }
        .onAppear { Task { await model.refresh() } }
    }

    // MARK: - Sekcje

    @ViewBuilder
    private func content(_ data: DashboardData) -> some View {
        topbar(confidence: data.confidence, days: data.coverageDays)

        Text(data.dateLabel)
            .font(AtlasFont.mono(12))
            .foregroundStyle(Palette.muted)
            .padding(.top, 18)

        hero(data)

        HStack(alignment: .top, spacing: 12) {
            baseCard(data)
            todayCard(data)
        }
        .padding(.top, 20)

        strip(data)

        if let note = data.note {
            noteCard(note)
        }

        breakdown(data)
    }

    private func topbar(confidence: Int, days: Int) -> some View {
        HStack {
            HStack(spacing: 0) {
                Text("LONGEVITY")
                Text(".").foregroundStyle(Palette.ochre)
            }
            .font(AtlasFont.display(15, .heavy))
            .tracking(2.1)
            .foregroundStyle(Palette.ink)

            Spacer()

            HStack(spacing: 7) {
                ZStack {
                    Circle().stroke(Palette.line, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(confidence) / 100)
                        .stroke(Palette.pine, lineWidth: 3)
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 9, height: 9)

                Text("pewność \(confidence)%")
                    .font(AtlasFont.mono(11))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Palette.panel, in: Capsule())
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
            .accessibilityLabel("Pewność \(confidence) procent, \(days) dni z danymi z ostatnich 30")
        }
    }

    private func hero(_ data: DashboardData) -> some View {
        VStack(spacing: 0) {
            Text("\(data.headline)")
                .font(AtlasFont.display(112, .bold))
                .tracking(-3)
                .monospacedDigit()
                .foregroundStyle(Palette.ochre)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())

            Kicker(text: "wynik długowieczności", size: 11)
                .padding(.top, 8)

            Text(data.stateText)
                .font(AtlasFont.body(15.5, .medium))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func baseCard(_ data: DashboardData) -> some View {
        card {
            Kicker(text: "Podstawa", color: Palette.pine)
            // Liczba dni realnie objętych średnią, nie deklarowane 30 —
            // przy jednym snapshocie "średnia z 30 dni" byłaby kłamstwem.
            Text("średnia z \(data.coverageDays) \(PL.daysGenitive(data.coverageDays))")
                .font(AtlasFont.body(11))
                .foregroundStyle(Palette.muted)
                .padding(.top, 3)

            Text("\(data.baseline)")
                .font(AtlasFont.display(46))
                .monospacedDigit()
                .foregroundStyle(Palette.pine)
                .padding(.top, 10)

            if data.coverageDays > 1 {
                trendPill(data.baselineDelta)
                Sparkline(values: data.baselineSeries)
                    .padding(.top, 10)
            }

            Text("Zmienia się powoli — nie reaguje na jeden dzień.")
                .font(AtlasFont.body(11.5))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .padding(.top, 10)
        }
    }

    private func todayCard(_ data: DashboardData) -> some View {
        card {
            Kicker(text: "Dziś", color: Palette.ochreInk)
            Text("z dzisiejszych pomiarów")
                .font(AtlasFont.body(11))
                .foregroundStyle(Palette.muted)
                .padding(.top, 3)

            Text("\(data.today)")
                .font(AtlasFont.display(46))
                .monospacedDigit()
                .foregroundStyle(Palette.ochre)
                .padding(.top, 10)

            Text(data.todayWord)
                .font(AtlasFont.body(11.5))
                .foregroundStyle(Palette.muted)
                .padding(.top, 10)

            Text("Liczy się od nowa każdego dnia. To ona rusza wynikiem.")
                .font(AtlasFont.body(11))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .padding(.top, 12)
        }
    }

    private func trendPill(_ delta: Int) -> some View {
        let arrow = delta > 0 ? "↗" : (delta < 0 ? "↘" : "→")
        let sign = delta > 0 ? "+" : ""
        return Text("\(arrow) \(sign)\(delta) / 7 dni")
            .font(AtlasFont.mono(10.5, .bold))
            .foregroundStyle(Palette.pine)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.pineSoft, in: Capsule())
            .padding(.top, 9)
    }

    private func strip(_ data: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: PL.lastDays(data.points.count))
                .padding(.bottom, 4)

            if data.points.count > 1 {
                TrendStrip(points: data.points)

                VStack(alignment: .leading, spacing: 6) {
                    legend(color: Palette.pine, isLine: true, text: "Podstawa — pełznie powoli")
                    legend(color: Palette.ochre, isLine: false, text: "Wynik dnia — skacze codziennie")
                }
                .padding(.top, 8)
            } else {
                Text("Za mało danych na wykres — potrzebne min. 2 dni z check-inem.")
                    .font(AtlasFont.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(3)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 15)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
        .padding(.top, 20)
    }

    private func legend(color: Color, isLine: Bool, text: String) -> some View {
        HStack(spacing: 7) {
            if isLine {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 16, height: 3)
            } else {
                Circle().fill(color).frame(width: 9, height: 9)
                    .frame(width: 16)
            }
            Text(text)
                .font(AtlasFont.body(11))
                .foregroundStyle(Palette.muted)
        }
    }

    private func noteCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("↳")
                .font(AtlasFont.body(13, .bold))
                .foregroundStyle(Palette.pine)
            Text(text)
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
        .padding(.top, 14)
    }

    private func breakdown(_ data: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Kicker(text: "co składa się na wynik")
                .padding(.bottom, 1)

            ForEach(data.breakdown) { row in
                componentRow(row)
            }

            if data.breakdown.contains(where: \.hasParts) {
                Text("Dotknij komponentu, żeby zobaczyć, z czego się składa.")
                    .font(AtlasFont.mono(9.5))
                    .foregroundStyle(Palette.tick)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private func componentRow(_ row: ScoreComponentRow) -> some View {
        let isOpen = expanded.contains(row.id)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    if isOpen { expanded.remove(row.id) } else { expanded.insert(row.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Text(row.label)
                            .font(AtlasFont.body(12.5))
                            .foregroundStyle(Palette.ink)
                        // Waga mówi, ile ten komponent w ogóle waży w wyniku —
                        // bez niej pasek na 100 przy metabolizmie wygląda tak
                        // samo ważnie jak pasek na 100 przy śnie.
                        if let weight = row.weight {
                            Text("\(Int((weight * 100).rounded()))%")
                                .font(AtlasFont.mono(9.5))
                                .foregroundStyle(Palette.tick)
                        }
                        if row.hasParts {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Palette.tick)
                                .rotationEffect(.degrees(isOpen ? 90 : 0))
                        }
                    }
                    .frame(width: 118, alignment: .leading)

                    bar(value: row.value, color: Palette.ochre, height: 7)

                    Text("\(Int(row.value.rounded()))")
                        .font(AtlasFont.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                        .frame(width: 34, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!row.hasParts)
            .accessibilityElement(children: .combine)
            .accessibilityHint(row.hasParts ? "Dotknij, żeby rozwinąć składowe" : "")

            if isOpen {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(row.parts) { part in
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Text(part.label)
                                    .font(AtlasFont.body(11.5))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                                Text("\(Int((part.weight * 100).rounded()))%")
                                    .font(AtlasFont.mono(9))
                                    .foregroundStyle(Palette.tick)
                            }
                            .frame(width: 128, alignment: .leading)

                            if let value = part.value {
                                bar(value: value, color: Palette.stem, height: 5)
                                Text("\(Int(value.rounded()))")
                                    .font(AtlasFont.mono(10))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.tick)
                                    .frame(width: 34, alignment: .trailing)
                            } else {
                                // Brak pomiaru nie dostaje paska — pusty pasek
                                // czytałby się jak wynik zerowy.
                                Text("nie zmierzono")
                                    .font(AtlasFont.mono(9.5))
                                    .foregroundStyle(Palette.tick)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer().frame(width: 34)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.leading, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func bar(value: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.panel)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(max(0, min(value, 100)) / 100))
            }
        }
        .frame(height: height)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Text("Wynik v3 — średnia ważona pomiarów. Komponenty bez danych są pomijane,\na wagi pozostałych przenormowane.")
                .font(AtlasFont.mono(10.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button("Wyloguj") {
                Task { try? await AppSupabase.client.auth.signOut() }
            }
            .font(AtlasFont.body(13))
            .tint(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 15)
            .padding(.top, 15)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
    }

    private func placeholder<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack { content() }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 120)
    }
}

#Preview("Z danymi") {
    DashboardView(model: DashboardViewModel(state: .loaded(.sample)))
}

#Preview("Pusty") {
    DashboardView(model: DashboardViewModel(state: .empty))
}
