import SwiftUI

struct DashboardView: View {
    /// Rozwinięte komponenty rozbicia — id zamiast indeksu, bo lista zmienia
    /// długość razem z pokryciem danych.
    @State private var expanded: Set<String> = []

    /// Dzień wskazany palcem na wykresie. `nil` = wykres pokazuje dziś.
    @State private var selectedDay: Int?

    @State private var showsExplainer = false

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
                            // Check-in (stres, nastrój) wypadł ze score'u razem
                            // z v2 — sam nie stworzy snapshotu. Wynik robią
                            // pomiary, i tak ma brzmieć rada.
                            Text("Zsynchronizuj dane zdrowotne albo dodaj pomiary — wynik pojawi się tutaj.")
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.card)
        .statusBarCover()
        .refreshable { await model.load() }
        .onAppear { Task { await model.refresh() } }
        .sheet(isPresented: $showsExplainer) {
            ScoreExplainerSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Sekcje

    /// Kolejność odpowiada pytaniom, które ekran ma zamykać: ile mam dziś →
    /// czy to dużo jak na mnie → jak szło ostatnio → co to napędza.
    @ViewBuilder
    private func content(_ data: DashboardData) -> some View {
        topbar(data)

        hero(data)

        chartSection(data)

        if let note = data.note {
            noteCard(note)
        }

        breakdown(data)

        explainerButton
    }

    /// Data w pigułce przy tytule, a nie osobną linią pod nim: mówi tyle samo,
    /// a nie zabiera całego wiersza tuż nad wielką cyfrą.
    private func topbar(_ data: DashboardData) -> some View {
        HStack {
            ScreenTitle(text: "Longevity")

            Spacer()

            Text(data.dateLabel)
                .font(AtlasFont.mono(11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Palette.panel, in: Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        }
    }

    /// Jedna wielka liczba — dzisiejszy wynik. Trend nie dostaje własnej cyfry,
    /// tylko wchodzi tu jako relacja, żeby ekran nie miał dwóch konkurujących
    /// liczb do porównania.
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

            // „Wynik dnia", nie „wynik długowieczności" — ta liczba jest
            // z dzisiaj i etykieta ma to mówić sama, bez osobnej karty „Dziś".
            Kicker(text: "wynik dnia", size: 11)
                .padding(.top, 8)

            trendPill(data)
                .padding(.top, 12)

            Text(data.stateText)
                .font(AtlasFont.body(15.5, .medium))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
    }

    /// Pigułka jest neutralna kolorystycznie w obie strony — kierunek niesie
    /// strzałka. Czerwień przy spadku kłóciłaby się z tym, co mówi appka:
    /// pojedynczy dzień nie jest powodem do paniki.
    @ViewBuilder
    private func trendPill(_ data: DashboardData) -> some View {
        if let trend = data.trend, let delta = data.trendDelta {
            // `String(localized:)`, bo zdanie powstaje w `switch`, a nie wprost
            // w `Text` — sam literał przypisany do zmiennej nie trafiłby do
            // String Catalogu i został po polsku.
            let label = switch delta {
            case 1...: String(localized: "↗ \(delta) ponad trend (\(trend))")
            case ..<0: String(localized: "↘ \(abs(delta)) poniżej trendu (\(trend))")
            default: String(localized: "→ równo z trendem (\(trend))")
            }

            Text(label)
                .font(AtlasFont.mono(11, .bold))
                .foregroundStyle(Palette.pine)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.pineSoft, in: Capsule())
                .contentTransition(.numericText())
        } else {
            // Licznik mówi, ile dni DOŁOŻYĆ, a nie ile trzeba mieć łącznie —
            // dzisiejszy pomiar już się liczy i wejdzie do jutrzejszego okna.
            // Inaczej przy trzech dniach z rzędu ekran kazał czekać na trzy dni.
            Text(
                data.trendMissingDays == 0
                    ? "trend pojawi się jutro"
                    : "jeszcze \(data.trendMissingDays) dni z pomiarami i pojawi się trend"
            )
            .font(AtlasFont.mono(11))
            .foregroundStyle(Palette.tick)
        }
    }

    @ViewBuilder
    private func chartSection(_ data: DashboardData) -> some View {
        if data.isWarmingUp {
            warmupCard(data)
        } else {
            stripCard(data)
        }
    }

    private func stripCard(_ data: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Kicker(text: "ostatnie \(data.points.count) dni")
                Spacer()
                // Data pojawia się dopiero pod palcem — bez niej nie wiadomo,
                // którą kropkę czyta wielka liczba nad wykresem. Poza
                // przeciąganiem slot zajmuje licznik pokrycia: stoi przy
                // wykresie, który opisuje, zamiast przy nazwie appki.
                if let index = selectedDay, data.points.indices.contains(index) {
                    Text(TrendStrip.longDay(data.points[index].date))
                        .font(AtlasFont.mono(10.5))
                        .foregroundStyle(Palette.ochreInk)
                } else {
                    Text("\(data.coverageDays) z 30 dni z pomiarami")
                        .font(AtlasFont.mono(10.5))
                        .foregroundStyle(Palette.tick)
                        .accessibilityLabel("\(data.coverageDays) dni z pomiarami z ostatnich 30")
                }
            }

            TrendStrip(points: data.points, selection: $selectedDay)

            HStack(spacing: 16) {
                legend(color: Palette.ochre, isLine: false, text: "wynik dnia")
                // Licznik mówi, ile dni z ostatnich siedmiu miało pomiar —
                // przy dziurach „trend z 7 dni" byłoby nieprawdą.
                legend(
                    color: Palette.pine,
                    isLine: true,
                    text: data.trend == nil
                        ? "trend — za mało dni"
                        : "trend z \(data.trendDays) dni"
                )
            }
            .padding(.top, 2)

            Text("Przeciągnij po wykresie, żeby odczytać dzień.")
                .font(AtlasFont.mono(9.5))
                .foregroundStyle(Palette.tick)
                .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 15)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
        .padding(.top, 22)
    }

    /// Zanim uzbiera się tydzień, wykres kłamie — więc zamiast niego jeden
    /// uczciwy licznik. Wcześniej to samo mówiły trzy różne elementy naraz
    /// („średnia z 2 dni", „0 / 7 dni", „ostatnie 2 dni").
    private func warmupCard(_ data: DashboardData) -> some View {
        let target = DashboardData.warmupDays

        return VStack(alignment: .leading, spacing: 0) {
            Kicker(text: "zbieram dane")

            Text("Dzień \(data.coverageDays) z \(target)")
                .font(AtlasFont.display(26))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .padding(.top, 6)

            bar(
                value: Double(data.coverageDays) / Double(target) * 100,
                color: Palette.pine,
                height: 7
            )
            .padding(.top, 12)

            Text("Wykres i trend włączą się po \(target) dniach z pomiarami.")
                .font(AtlasFont.body(12))
                .foregroundStyle(Palette.muted)
                .lineSpacing(3)
                .padding(.top, 12)

            // Same dni z pomiarem — puste sloty kalendarza nie mają tu czego
            // pokazać, a licznik „Dzień 3 z 7" i tak mówi, ile ich jest.
            let measured = data.points.compactMap(\.total)

            if measured.count > 1 {
                Kicker(text: "zebrane wyniki", size: 9)
                    .padding(.top, 16)

                HStack(spacing: 6) {
                    ForEach(Array(measured.enumerated()), id: \.offset) { index, total in
                        let isToday = index == measured.count - 1
                        Text("\(Int(total))")
                            .font(AtlasFont.mono(11, .bold))
                            .monospacedDigit()
                            .foregroundStyle(isToday ? Palette.ochreInk : Palette.muted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isToday ? Palette.ochreSoft : Palette.panel, in: Capsule())
                    }
                }
                .padding(.top, 7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 15)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
        .padding(.top, 22)
    }

    private func legend(color: Color, isLine: Bool, text: LocalizedStringResource) -> some View {
        HStack(spacing: 6) {
            if isLine {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 3)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
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
        }
        .padding(.top, 22)
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

    private var explainerButton: some View {
        Button { showsExplainer = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                Text("Jak liczymy wynik?")
            }
            .font(AtlasFont.body(13, .medium))
            .foregroundStyle(Palette.pine)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
    }

    private func placeholder<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack { content() }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 120)
    }
}

/// Copy, które wcześniej stało na stałe pod dużą cyfrą i zajmowało dwie karty.
/// Czyta się je raz, więc mieszka w arkuszu, a nie w najlepszym miejscu ekranu.
struct ScoreExplainerSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    entry(
                        "Wynik dnia",
                        Palette.ochreInk,
                        "Twoja dzisiejsza forma w jednej liczbie. Liczymy ją od nowa każdego dnia z pomiarów zegarka i tego, co dopisujesz w czacie. Dlatego potrafi skakać — jedną kiepską noc widać od razu."
                    )
                    entry(
                        "Trend",
                        Palette.pine,
                        "Twój zwykły poziom z ostatniego tygodnia. Rusza się wolno, więc mówi, w którą stronę naprawdę idziesz — a nie czy akurat dziś było lepiej. Dzisiejszy wynik go nie podbija, więc porównanie z nim jest uczciwe."
                    )
                    entry(
                        "Zebrane dni",
                        Palette.muted,
                        "Ile z ostatnich 30 dni ma pomiary. Dzień bez pomiarów nie dostaje wyniku, a im mniej dni uzbierasz, tym bardziej trend wisi na pojedynczym z nich. Wystarczy nosić zegarek."
                    )
                    entry(
                        "Skąd bierze się liczba",
                        Palette.muted,
                        "Składają się na nią sen, wydolność, skład ciała, regeneracja i badania krwi. Każde waży inaczej — sen najmocniej. Czego nie zmierzysz, tego nie zgadujemy: brakujące obszary wypadają z rachunku, a udział biorą na siebie pozostałe."
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.card)
            // Bez przycisku zamykania — arkusz zbija się gestem albo
            // dotknięciem tła, a „Gotowe" sugerowałoby, że jest tu coś
            // do zatwierdzenia.
            .navigationTitle("Jak liczymy wynik")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func entry(_ title: LocalizedStringResource, _ color: Color, _ body: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Kicker(text: title, color: color, size: 10.5)
            Text(body)
                .font(AtlasFont.body(14))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
        }
    }
}

#Preview("Z danymi") {
    DashboardView(model: DashboardViewModel(state: .loaded(.sample)))
}

#Preview("Rozgrzewka") {
    DashboardView(model: DashboardViewModel(state: .loaded(.warmingUp)))
}

#Preview("Z przerwą w pomiarach") {
    DashboardView(model: DashboardViewModel(state: .loaded(.withGap)))
}

#Preview("Pusty") {
    DashboardView(model: DashboardViewModel(state: .empty))
}

#Preview("Wyjaśnienie") {
    ScoreExplainerSheet()
}
