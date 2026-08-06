import PhotosUI
import SwiftUI

struct ChatView: View {
    @State private var model: ChatViewModel

    @State private var showMealOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showActivity = false
    @State private var showCheckin = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var composerFocused: Bool

    init(model: ChatViewModel = ChatViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            feed
            quickActions
            composer
        }
        .background(Palette.panel)
        .task {
            if model.isLoadingHistory { await model.load() }
        }
        .confirmationDialog("Dodaj posiłek", isPresented: $showMealOptions, titleVisibility: .visible) {
            Button("Zrób zdjęcie") { showCamera = true }
            Button("Wybierz z galerii") { showPhotoPicker = true }
            Button("Opisz słowami") {
                model.startMealDescription()
                composerFocused = true
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Im więcej szczegółów, tym dokładniejsza analiza.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                Task { await model.logMeal(photo: data) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showActivity) {
            ActivitySheet { minutes in
                Task { await model.logActivity(minutes: minutes) }
            }
        }
        .sheet(isPresented: $showCheckin) {
            CheckinSheet { sleep, stress, mood in
                Task { await model.saveCheckin(sleep: sleep, stress: stress, mood: mood) }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                photoItem = nil
                guard let data else { return }
                await model.logMeal(photo: data)
            }
        }
    }

    // MARK: - Sekcje

    private var header: some View {
        HStack {
            HStack(spacing: 0) {
                Text("ASYSTENT")
                Text(".").foregroundStyle(Palette.ochre)
            }
            .font(AtlasFont.display(15, .heavy))
            .tracking(2.1)
            .foregroundStyle(Palette.ink)

            Spacer()

            if model.isBusy {
                ProgressView().tint(Palette.pine).scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Palette.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.isLoadingHistory {
                        ProgressView().tint(Palette.pine)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if model.messages.isEmpty {
                        welcome
                    }

                    ForEach(model.messages) { message in
                        bubble(for: message).id(message.id)
                    }

                    // Kotwica przewijania — samo `messages.last` nie wystarcza,
                    // bo dymek rośnie po dodaniu i koniec ucieka poza ekran.
                    Color.clear.frame(height: 1).id(scrollAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(scrollAnchor, anchor: .bottom)
                }
            }
        }
    }

    private var scrollAnchor: String { "bottom" }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cześć 👋")
                .font(AtlasFont.display(24))
                .foregroundStyle(Palette.ink)

            Text("Wszystko, co robiłeś przez Telegram, jest teraz tutaj.")
                .font(AtlasFont.body(14.5))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 9) {
                welcomeRow("🍽️", "Wrzuć zdjęcie posiłku — policzę kalorie i makro")
                welcomeRow("🏃", "Dopisz aktywność jednym tapnięciem")
                welcomeRow("✅", "Zrób check-in: sen, stres, nastrój")
                welcomeRow("🧠", "Zapytaj o cokolwiek — znam Twoje dane")
            }
            .padding(.top, 2)

            Text("Odpowiadam na podstawie Twojego score'u, check-inów, wagi i badań.")
                .font(AtlasFont.mono(11))
                .foregroundStyle(Palette.muted)
                .lineSpacing(3)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
        .padding(.top, 30)
    }

    private func welcomeRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon).font(.system(size: 14))
            Text(text)
                .font(AtlasFont.body(13.5))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
        }
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        switch message.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 50)
                Text(text)
                    .font(AtlasFont.body(14.5))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.pine, in: RoundedRectangle(cornerRadius: 16))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant(let markdown):
            HStack {
                Text(Self.attributed(markdown))
                    .font(AtlasFont.body(14.5))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
                Spacer(minLength: 40)
            }

        case .meal(let card):
            MealCardView(card: card)

        case .confirmation(let text):
            Text(text)
                .font(AtlasFont.mono(11.5))
                .foregroundStyle(Palette.pine)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Palette.pineSoft, in: Capsule())
                .frame(maxWidth: .infinity)

        case .failure(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("⚠️").font(.system(size: 12))
                Text(text)
                    .font(AtlasFont.body(12.5))
                    .foregroundStyle(Palette.ochreInk)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ochreSoft, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("🍽️", "Posiłek") { showMealOptions = true }
                chip("🏃", "Aktywność") { showActivity = true }
                chip("✅", "Check-in") { showCheckin = true }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Palette.panel)
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
    }

    private func chip(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 13))
                Text(label)
                    .font(AtlasFont.body(13, .medium))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Palette.card, in: Capsule())
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(model.placeholder, text: $model.draft, axis: .vertical)
                .font(AtlasFont.body(14.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(model.isComposingMeal ? Palette.ochre : Palette.line, lineWidth: 1)
                )

            Button {
                composerFocused = false
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(canSend ? Palette.pine : Palette.tick, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Palette.panel)
    }

    private var canSend: Bool {
        !model.isBusy && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Serwer odsyła Markdown, bo tylko Telegram renderuje HTML-a z `lib/assistant.ts`.
    private static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}

/// Wynik analizy posiłku — układ jak wiadomość, którą wysyła bot.
private struct MealCardView: View {
    let card: MealCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.title)
                .font(AtlasFont.display(17))
                .foregroundStyle(Palette.ink)

            Kicker(text: card.category)
                .padding(.top, 3)

            if let min = card.kcalMin, let max = card.kcalMax {
                Text("\(min)–\(max) kcal")
                    .font(AtlasFont.display(24))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ochre)
                    .padding(.top, 9)
            }

            if let protein = card.proteinG, let carbs = card.carbsG, let fat = card.fatG {
                Text("B \(Self.grams(protein)) • W \(Self.grams(carbs)) • T \(Self.grams(fat))")
                    .font(AtlasFont.mono(11.5))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 5)
            }

            if let score = card.score {
                HStack(spacing: 8) {
                    Text("Meal score")
                        .font(AtlasFont.body(11.5))
                        .foregroundStyle(Palette.muted)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.panel)
                            Capsule()
                                .fill(Palette.pine)
                                .frame(width: geo.size.width * CGFloat(score) / 100)
                        }
                    }
                    .frame(height: 6)

                    Text("\(score)")
                        .font(AtlasFont.mono(11, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.pine)
                }
                .padding(.top, 12)
            }

            if let insight = card.insight {
                Text(insight)
                    .font(AtlasFont.body(13))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
                    .padding(.top, 12)
            }

            if let action = card.action {
                HStack(alignment: .top, spacing: 8) {
                    Text("↳")
                        .font(AtlasFont.body(12, .bold))
                        .foregroundStyle(Palette.pine)
                    Text(action)
                        .font(AtlasFont.body(12.5))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(2)
                }
                .padding(.top, 8)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
    }

    private static func grams(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))g" : String(format: "%.1fg", value)
    }
}

#Preview("Pusty") {
    ChatView(model: ChatViewModel(isLoadingHistory: false))
}

#Preview("Z rozmową") {
    ChatView(
        model: ChatViewModel(
            messages: [
                ChatMessage(kind: .user("co z moim snem w tym tygodniu?")),
                ChatMessage(
                    kind: .assistant(
                        "**Wniosek**\nSen jest Twoim najsłabszym składnikiem — 62/100 przy średniej 74.\n\n**Co zrobić dziś**\n1) Stała godzina snu.\n2) Kofeina do 14:00."
                    )
                ),
                ChatMessage(
                    kind: .meal(
                        MealCard(
                            title: "Kurczak z ryżem",
                            category: "Obiad",
                            kcalMin: 620,
                            kcalMax: 780,
                            proteinG: 48,
                            carbsG: 72,
                            fatG: 18,
                            score: 74,
                            insight: "Dobre białko i sensowna porcja węglowodanów.",
                            action: "Dorzuć warzywa — podniesie błonnik i sytość."
                        )
                    )
                ),
                ChatMessage(kind: .confirmation("🏃 Aktywność zapisana: 45 min")),
            ],
            isLoadingHistory: false
        )
    )
}
