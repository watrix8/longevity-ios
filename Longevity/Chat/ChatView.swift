import PhotosUI
import SwiftUI

struct ChatView: View {
    @State private var model: ChatViewModel

    @State private var showMealOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showActivity = false
    @State private var showCheckin = false
    @State private var showMarkers = false
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
            Text("Ocenię, co widać na talerzu — bez liczenia kalorii.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                Task { await model.adviseMeal(photo: data) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showActivity) {
            ActivitySheet { minutes in
                Task { await model.logActivity(minutes: minutes) }
            }
        }
        .sheet(isPresented: $showCheckin) {
            CheckinSheet { stress, mood in
                Task { await model.saveCheckin(stress: stress, mood: mood) }
            }
        }
        .sheet(isPresented: $showMarkers) {
            MarkersSheet { markers in
                Task { await model.saveMarkers(markers) }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                photoItem = nil
                guard let data else { return }
                await model.adviseMeal(photo: data)
            }
        }
    }

    // MARK: - Sekcje

    private var header: some View {
        HStack {
            ScreenTitle(text: "Asystent")

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
            // Rosnący dymek nie zmienia liczby wiadomości, a i tak spycha
            // koniec odpowiedzi poza ekran. Bez animacji, bo przy kilkudziesięciu
            // kawałkach na sekundę nakładałyby się na siebie.
            .onChange(of: model.streamTick) { _, _ in
                proxy.scrollTo(scrollAnchor, anchor: .bottom)
            }
        }
    }

    private var scrollAnchor: String { "bottom" }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cześć 👋")
                .font(AtlasFont.display(24))
                .foregroundStyle(Palette.ink)

            Text("Tu zapisujesz dzień i pytasz o to, czego nie widać w liczbach.")
                .font(AtlasFont.body(14.5))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 9) {
                welcomeRow("🍽️", "Pokaż posiłek — powiem, co o nim myślę")
                welcomeRow("🏃", "Dopisz aktywność jednym tapnięciem")
                welcomeRow("✅", "Zrób check-in: stres i nastrój")
                welcomeRow("📏", "Dopisz pomiary, których nie ma w Apple Health")
                welcomeRow("🧠", "Zapytaj o cokolwiek — znam Twoje dane")
            }
            .padding(.top, 2)

            Text("Odpowiadam na podstawie Twojego score'u, pomiarów z zegarka, wagi i badań.")
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
                AssistantMarkdownView(markdown: markdown)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
                Spacer(minLength: 40)
            }

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
                chip("📏", "Pomiary") { showMarkers = true }
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
                ChatMessage(kind: .confirmation("🏃 Aktywność zapisana: 45 min")),
            ],
            isLoadingHistory: false
        )
    )
}
