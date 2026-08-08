import SwiftUI

/// Druga połowa rejestracji — odpowiednik `app/onboarding/page.tsx`.
///
/// Pokazuje się nad zakładkami, a nie zamiast nich, bo bramkę stawia dopiero
/// udany odczyt profilu: dane wpisane przy zerwanej sieci i tak nie miałyby
/// gdzie wylądować.
struct OnboardingView: View {
    @Bindable var model: OnboardingViewModel

    @State private var showSignOutConfirm = false
    @FocusState private var focused: Field?

    private enum Field { case name, height, weight }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    form
                    errorMessage
                    primaryButton
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .statusBarCover()
        }
    }

    // MARK: - Sekcje

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("LONGEVITY")
                Text(verbatim: ".").foregroundStyle(Palette.ochre)
            }
            .font(AtlasFont.display(26, .heavy))
            .tracking(3.6)
            .foregroundStyle(Palette.ink)

            Kicker(text: "uzupełnij profil", size: 11)

            Text("Wiek, płeć, wzrost i waga wchodzą wprost do wyniku. Bez nich policzymy go z połowy składników.")
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.muted)
                .lineSpacing(3)
                .padding(.top, 6)
        }
        .padding(.bottom, 26)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                row("Imię", isMissing: model.fullName.trimmingCharacters(in: .whitespaces).isEmpty) {
                    TextField("—", text: $model.fullName)
                        .font(AtlasFont.body(14))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.givenName)
                        .tint(Palette.pine)
                        .submitLabel(.next)
                        .focused($focused, equals: .name)
                        .onSubmit { focused = .height }
                }
                divider
                row("Data urodzenia", isMissing: !model.birthDateIsSet) {
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
                    .tint(Palette.pine)
                }
                divider
                row("Płeć", isMissing: model.sex.isEmpty) {
                    menu($model.sex, SettingsOptions.sexes)
                }
                divider
                row("Wzrost", isMissing: OnboardingViewModel.parseHeight(model.heightCm) == nil) {
                    measureField($model.heightCm, suffix: "cm", field: .height)
                }
                divider
                row("Waga", isMissing: OnboardingViewModel.parseWeight(model.weightKg) == nil) {
                    measureField($model.weightKg, suffix: "kg", field: .weight)
                }
                divider
                row("Główny cel", isMissing: model.primaryGoal.isEmpty) {
                    menu($model.primaryGoal, SettingsOptions.goals)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))

            Text("Kropka na marginesie znaczy, że pole czeka na uzupełnienie. Wszystko zmienisz później w Opcjach.")
                .font(AtlasFont.body(11.5))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .padding(.top, 8)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let message = model.errorMessage {
            Text(message)
                .font(AtlasFont.body(12.5))
                .foregroundStyle(.red)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
        }
    }

    private var primaryButton: some View {
        Button {
            focused = nil
            Task { await model.save() }
        } label: {
            Group {
                if model.isSaving {
                    ProgressView().tint(Palette.card)
                } else {
                    Text("Zapisz i zaczynamy")
                }
            }
            .font(AtlasFont.body(15, .semibold))
            // Stan wyglądu zależy od kompletności formularza, nie od `canSubmit` —
            // inaczej podczas zapisu tło bladnie i biały spinner znika.
            .foregroundStyle(isFilled ? Palette.card : Palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            // Zielony jak każda inna akcja; stan wyłączony biały z obwódką,
            // bo `ochreSoft` na tle strony ma kontrast 1,07:1. Ten sam wzór
            // co przycisk na ekranie logowania.
            .background(
                isFilled ? Palette.pine : Palette.card,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                if !isFilled {
                    RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.canSubmit)
        .padding(.top, 20)
    }

    /// Bez wyjścia formularz byłby pułapką dla kogoś, kto zalogował się na złe konto.
    private var signOutButton: some View {
        Button("Wyloguj") { showSignOutConfirm = true }
            .font(AtlasFont.body(13))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .confirmationDialog(
                "Wylogować z aplikacji?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Wyloguj", role: .destructive) { Task { await model.signOut() } }
                Button("Anuluj", role: .cancel) {}
            }
    }

    private var isFilled: Bool { model.canSubmit || model.isSaving }

    // MARK: - Klocki

    /// Ochrowa kropka nazywa brakujące pole — bez niej wyszarzony przycisk nie
    /// mówi, czego jeszcze brakuje.
    ///
    /// Siedzi na marginesie, a nie w wierszu, bo w środku zabierałaby szerokość
    /// etykiecie. Ta i tak ustępuje wartości (długie „Lepsza forma sportowa"
    /// zostaje w całości, „Główny cel" się skraca), więc każdy punkt szerokości
    /// zjadał ją dosłownie.
    private func row<C: View>(
        _ label: LocalizedStringResource,
        isMissing: Bool,
        @ViewBuilder _ content: () -> C
    ) -> some View {
        HStack(spacing: 12) {
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
        .overlay(alignment: .leading) {
            Circle()
                .fill(Palette.ochre)
                .frame(width: 5, height: 5)
                .padding(.leading, 5)
                .opacity(isMissing ? 1 : 0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(isMissing ? Text("Pole wymaga uzupełnienia") : Text(""))
    }

    private func measureField(
        _ value: Binding<String>,
        suffix: LocalizedStringResource,
        field: Field
    ) -> some View {
        HStack(spacing: 4) {
            TextField("—", text: value)
                .font(AtlasFont.body(14))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .tint(Palette.pine)
                .focused($focused, equals: field)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 40, alignment: .trailing)
            Text(suffix)
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.muted)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(height: 1)
            .padding(.leading, 15)
    }

    private func menu(_ selection: Binding<String>, _ options: [(String, String)]) -> some View {
        Picker("", selection: selection) {
            Text(verbatim: "—").tag("")
            ForEach(options, id: \.0) { value, label in
                Text(label).tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(Palette.pine)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

#Preview {
    OnboardingView(model: OnboardingViewModel())
}
