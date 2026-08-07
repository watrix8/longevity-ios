import SwiftUI

struct SettingsView: View {
    @State private var model = SettingsViewModel()
    /// Współdzielona instancja — synchronizację odpala też powrót apki na wierzch,
    /// a ekran ma pokazywać ten sam stan, nie własną kopię.
    @State private var health = HealthSyncModel.shared
    @State private var showPasswordResetConfirm = false
    @State private var showSignOutConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                switch (model.isLoading, model.loadError) {
                case (true, _):
                    ProgressView()
                        .tint(Palette.pine)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 100)
                case (_, .some(let message)):
                    loadFailure(message)
                default:
                    healthCard
                    appleHealthCard
                    securityCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.card)
        .task { await model.load() }
        .task { await health.refreshConnection() }
        // Zmiany lecą same; sygnatury pilnują, żeby wczytanie nie zapisywało zwrotnie.
        .onChange(of: model.profileSignature) { model.profileChanged() }
        .onDisappear { Task { await model.flushPendingSaves() } }
    }

    // MARK: - Nagłówek

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status po prawej w linii tytułu, jak spinner w Asystencie
            // i pigułka dni na Dashboardzie.
            HStack {
                ScreenTitle(text: "Opcje")
                Spacer()
                saveIndicator
            }
            Text("Zmiany zapisują się same.")
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.muted)
        }
        .padding(.bottom, 18)
    }

    /// Dyskretny status zamiast przycisków zapisu — widoczny tylko wtedy,
    /// gdy coś się dzieje albo poszło nie tak.
    @ViewBuilder
    private var saveIndicator: some View {
        switch model.saveState {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView().tint(Palette.muted)
        case .saved:
            chip("Zapisano", systemImage: "checkmark", color: Palette.pine)
                .transition(.opacity)
        case .failed:
            chip("Nie zapisano", systemImage: "exclamationmark.triangle.fill", color: .red)
        }
    }

    private func chip(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            Text(text).font(AtlasFont.mono(10.5))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Palette.panel, in: Capsule())
        .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }

    // MARK: - Zdrowie i dane

    private var healthCard: some View {
        section(kicker: "zdrowie i dane") {
            row("Imię i nazwisko") {
                TextField("—", text: $model.fullName)
                    .font(AtlasFont.body(14))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.trailing)
                    .tint(Palette.ochre)
                    .submitLabel(.done)
            }
            divider
            row("Data urodzenia") {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { model.birthDate },
                        set: { model.setBirthDate($0) }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
                .tint(Palette.ochre)
            }
            divider
            row("Płeć") { menu($model.sex, SettingsOptions.sexes) }
            divider
            row("Wzrost") {
                numberField($model.heightCm, suffix: "cm")
            }
            divider
            row("Główny cel") { menu($model.primaryGoal, SettingsOptions.goals) }
            divider
            row("Sylwetka") { menu($model.bodyType, SettingsOptions.bodyTypes) }
        }
    }

    // MARK: - Apple Health

    private var appleHealthCard: some View {
        section(
            kicker: "apple health",
            footer: """
                Sen, VO₂max, tętno spoczynkowe, HRV, ruch, skład ciała i waga. \
                Wpis zrobiony ręcznie ma pierwszeństwo — zegarek go nie nadpisze. \
                Wagę i pozostałe pomiary dopisujesz w czacie, a oglądasz na Trendach.
                """
        ) {
            row("Połączenie") {
                if health.isConnected {
                    Text("Połączono")
                        .font(AtlasFont.body(14))
                        .foregroundStyle(Palette.pine)
                } else {
                    Button("Połącz") { Task { await health.connect() } }
                        .font(AtlasFont.body(14, .semibold))
                        .tint(Palette.ochreInk)
                        .disabled(health.isSyncing)
                }
            }
            divider
            row("Ostatnia synchronizacja") {
                if health.isSyncing {
                    ProgressView().tint(Palette.muted)
                } else {
                    Text(health.lastSyncedLabel)
                        .font(AtlasFont.body(14))
                        .foregroundStyle(Palette.muted)
                }
            }

            if health.isConnected {
                divider
                actionRow("Synchronizuj teraz", color: Palette.ochreInk) {
                    Task { await health.syncNow() }
                }
                .disabled(health.isSyncing)
            }

            if let sources = health.sources {
                divider
                row("Źródła danych") {
                    Text(sources.names.joined(separator: ", "))
                        .font(AtlasFont.body(13))
                        .foregroundStyle(sources.hasConflict ? Palette.ochreInk : Palette.muted)
                        .multilineTextAlignment(.trailing)
                }
                if sources.hasConflict {
                    divider
                    // Dwa urządzenia opisujące tę samą metrykę to nie ciekawostka:
                    // kroki i kalorie mogą się zsumować, a tętno uśrednić między
                    // różnymi metodami pomiaru.
                    Text("Więcej niż jedno źródło dla: \(sources.conflicting.joined(separator: ", ")). Wartości mogą się dublować.")
                        .font(AtlasFont.body(12))
                        .foregroundStyle(Palette.ochreInk)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                }
            }

            if let status = health.statusMessage {
                divider
                Text(status)
                    .font(AtlasFont.body(12))
                    .foregroundStyle(health.statusIsError ? .red : Palette.pine)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Bezpieczeństwo

    private var securityCard: some View {
        section(
            kicker: "bezpieczeństwo",
            footer: "Nowe hasło ustawisz przez link, który wyślemy na Twój adres."
        ) {
            row("Email") {
                Text(model.email)
                    .font(AtlasFont.body(14))
                    .foregroundStyle(Palette.muted)
            }
            divider
            // Hasła nie ustawia się w formularzu ustawień — standardowy wzorzec
            // to link wysłany na maila, obsłużony przez stronę `/update-password`.
            actionRow("Zmień hasło", color: Palette.ochreInk) {
                showPasswordResetConfirm = true
            }
            .disabled(model.isSendingReset || model.email.isEmpty)
            .confirmationDialog(
                "Wysłać link do zmiany hasła na \(model.email)?",
                isPresented: $showPasswordResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Wyślij link") { Task { await model.sendPasswordReset() } }
                Button("Anuluj", role: .cancel) {}
            }

            if let status = model.passwordStatus {
                divider
                Text(status)
                    .font(AtlasFont.body(12))
                    .foregroundStyle(model.passwordIsError ? .red : Palette.pine)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
            }

            divider
            actionRow("Wyloguj", color: .red) { showSignOutConfirm = true }
                .confirmationDialog(
                    "Wylogować z aplikacji?",
                    isPresented: $showSignOutConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Wyloguj", role: .destructive) {
                        Task { await model.signOut() }
                    }
                    Button("Anuluj", role: .cancel) {}
                }
        }
    }

    private func loadFailure(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text("Nie udało się wczytać ustawień")
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
        .padding(.vertical, 70)
    }

    // MARK: - Klocki

    private func section<C: View>(
        kicker: String,
        footer: String? = nil,
        @ViewBuilder _ content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: kicker)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))

            if let footer {
                Text(footer)
                    .font(AtlasFont.body(11.5))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 22)
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 12) {
            // Etykieta ustępuje wartości: przy długich opcjach ("Lepsza forma
            // sportowa") to ona ma się skrócić, a nie zawijać wybrana wartość.
            // Szerokość wymusza `fixedSize` na samym pickerze — `layoutPriority`
            // tutaj zabrałoby całą szerokość także polom tekstowym.
            Text(label)
                .font(AtlasFont.body(14))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            content()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }

    private func actionRow(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(AtlasFont.body(14))
                    .foregroundStyle(color)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(height: 1)
            .padding(.leading, 15)
    }

    private func numberField(_ value: Binding<String>, suffix: String) -> some View {
        HStack(spacing: 4) {
            TextField("—", text: value)
                .font(AtlasFont.body(14))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .tint(Palette.ochre)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 40, alignment: .trailing)
            Text(suffix)
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.muted)
        }
    }

    private func menu(_ selection: Binding<String>, _ options: [(String, String)]) -> some View {
        Picker("", selection: selection) {
            Text("—").tag("")
            ForEach(options, id: \.0) { value, label in
                Text(label).tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(Palette.ochre)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

#Preview {
    SettingsView()
}
