import PhotosUI
import SwiftUI

struct ChatView: View {
    /// Zmiana wartości to prośba o zjechanie na dół — rośnie, gdy użytkownik
    /// tapnie w już aktywną zakładkę asystenta.
    let bottomRequest: Int

    @State private var model: ChatViewModel

    @State private var showMealOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showActivity = false
    @State private var showCheckin = false
    @State private var showMarkers = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var composerFocused: Bool

    init(bottomRequest: Int = 0, model: ChatViewModel = ChatViewModel()) {
        self.bottomRequest = bottomRequest
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            feed
            quickActions
            composer
        }
        .background(Palette.paper)
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
                model.attach(photo: data)
                composerFocused = true
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
                model.attach(photo: data)
            }
        }
    }

    // MARK: - Sekcje

    private var header: some View {
        HStack {
            ScreenTitle(text: "Asystent")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Palette.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }

    /// Feed trzyma się dołu natywnymi kotwicami. Ręczne przewijanie zostaje
    /// wyłącznie na jawne żądanie użytkownika — tap w aktywną zakładkę.
    ///
    /// Sterowanie przewijaniem z ręki miało dwie wady naraz. Historia dociera
    /// po pojawieniu się widoku, więc `scrollTo` na zmianę liczby wiadomości
    /// leciało w tej samej klatce, w której stos dopiero układał wiersze —
    /// nie było do czego przewinąć i czat otwierał się na najstarszej
    /// wiadomości. A trafienie offsetem poza zmaterializowany zakres
    /// zostawiało pusty ekran do czasu, aż gest wymusił ponowne wyliczenie.
    ///
    /// Stos jest zachłanny i taki musi zostać. Leniwy potrafi ustawić się na
    /// dole zawartości, której jeszcze nie zbudował, i zostawić pusty ekran do
    /// czasu, aż gest wymusi wyliczenie — to właśnie ten objaw, przy którym
    /// „trzeba przejechać po ekranie, żeby coś się pojawiło".
    ///
    /// Kosztu nie ma się co bać: pomiar na realnej historii dał 227 bloków
    /// Markdownu w 18 ms. Wcześniejsze podejrzenie, że to układanie opóźnia
    /// klawiaturę, było hipotezą bez pomiaru — czekanie brało się z sieci,
    /// a to załatwia cache w `ChatHistoryCache`.
    private var feed: some View {
        ScrollViewReader { proxy in
            feedScroll
                .onChange(of: bottomRequest) { _, _ in
                    guard let last = model.messages.last?.id else { return }

                    // Odroczenie o cykl, bo w tej samej klatce wygrywa systemowy
                    // skok na górę, który iOS odpala przy tapnięciu w aktywną zakładkę.
                    Task { @MainActor in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
        }
    }

    private var feedScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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

                if model.isAwaitingReply {
                    TypingBubble()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .animation(.easeOut(duration: 0.2), value: model.isAwaitingReply)
        }
        // Otwarcie na najnowszej wiadomości.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        // Rosnący dymek w trakcie strumienia trzyma koniec odpowiedzi na
        // ekranie — to samo robiła wcześniej ręczna kotwica, tylko bez
        // wyścigu z układaniem widoku.
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
    }

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

    private func welcomeRow(_ icon: String, _ text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: icon).font(.system(size: 14))
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

        case .photo(let data, let caption):
            HStack {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 0) {
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipped()
                    }

                    if let caption {
                        Text(caption)
                            .font(AtlasFont.body(14.5))
                            .foregroundStyle(.white)
                            .lineSpacing(3)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 220, alignment: .leading)
                    }
                }
                .background(Palette.pine, in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant(let markdown):
            HStack {
                AssistantMarkdownView(markdown: markdown)
                    .equatable()
                    .textSelection(.enabled)
                    // Linki w `AttributedString` malują się ambientowym akcentem,
                    // a ten jest ochrowy od `TabView` — więc odnośnik do badania
                    // wychodził w kolorze zarezerwowanym dla „popatrz", nie
                    // „dotknij". Tint zawężony do dymka nie rusza zakładek.
                    .tint(Palette.pine)
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
                // Obwódka, bo tło strony to teraz papier, a nie biel: sam
                // `pineSoft` odcina się od niego na 1,10:1, czyli prawie wcale.
                .background(Palette.pineSoft, in: Capsule())
                .overlay(Capsule().stroke(Palette.pine.opacity(0.28), lineWidth: 1))
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
            // To samo co przy potwierdzeniu: `ochreSoft` na papierze to 1,07:1.
            .background(Palette.ochreSoft, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.stem, lineWidth: 1))
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
        .background(Palette.paper)
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
    }

    private func chip(_ icon: String, _ label: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: icon).font(.system(size: 13))
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
        VStack(alignment: .leading, spacing: 8) {
            if let photo = model.attachedPhoto, let image = UIImage(data: photo) {
                attachmentPreview(image)
            }

            composerRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Palette.paper)
    }

    /// Miniatura zdjęcia czekającego na wysłanie. Bez tego użytkownik nie ma
    /// jak sprawdzić, co właściwie podpiął, ani się z tego wycofać.
    private func attachmentPreview(_ image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.ochre, lineWidth: 1))

            Button {
                model.removeAttachment()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Palette.ink.opacity(0.75), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
            .accessibilityLabel("Usuń zdjęcie")
        }
        .padding(.top, 6)
        .padding(.trailing, 7)
    }

    private var composerRow: some View {
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
                    .background(model.canSend ? Palette.pine : Palette.tick, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
        }
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
