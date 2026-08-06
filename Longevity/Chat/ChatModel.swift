import Foundation
import Observation

/// Wiersz `assistant_messages` — historia rozmowy współdzielona z Telegramem.
private struct AssistantMessageRow: Decodable {
    let role: String
    let content: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case role, content
        case createdAt = "created_at"
    }
}

private struct ActivityPayload: Encodable {
    let user_id: String
    let logged_date: String
    let activity_minutes: Int
    let source: String
}

@MainActor
@Observable
final class ChatViewModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isLoadingHistory = true
    /// Blokuje composer na czas zapytania — asystent i wizja potrafią chwilę zająć.
    private(set) var isBusy = false

    var draft = ""

    /// Gdy analiza posiłku wróciła niepewna, następny wpisany tekst jest
    /// odpowiedzią na dopytanie, a nie pytaniem do asystenta. Odpowiednik
    /// `telegram_pending_inputs`, tylko po stronie klienta.
    private var pendingMeal: (id: String, imageBase64: String?)?

    /// Ustawiane przez „Opisz słowami" — bez tego opis posiłku poleciałby do
    /// asystenta jako zwykłe pytanie.
    private var awaitingMealDescription = false

    var isComposingMeal: Bool { pendingMeal != nil || awaitingMealDescription }

    var placeholder: String {
        if pendingMeal != nil { return "Odpowiedz na pytanie o posiłek…" }
        if awaitingMealDescription { return "Co jesz? Podaj też wielkość porcji…" }
        return "Zapytaj o cokolwiek…"
    }

    func startMealDescription() {
        awaitingMealDescription = true
    }

    init(messages: [ChatMessage] = [], isLoadingHistory: Bool = true) {
        self.messages = messages
        self.isLoadingHistory = isLoadingHistory
    }

    // MARK: - Historia

    func load() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        async let turns = loadConversation()
        async let meals = try? LongevityAPI.todaysMeals()

        let merged = await (turns + mealMessages(from: meals ?? []))
            .sorted { $0.at < $1.at }

        messages = merged
    }

    private func loadConversation() async -> [ChatMessage] {
        do {
            let rows: [AssistantMessageRow] = try await AppSupabase.client
                .from("assistant_messages")
                .select("role, content, created_at")
                .order("created_at", ascending: false)
                .limit(40)
                .execute()
                .value

            return rows.reversed().map { row in
                ChatMessage(
                    kind: row.role == "user" ? .user(row.content) : .assistant(row.content),
                    at: ChatDates.parseTimestamp(row.createdAt)
                )
            }
        } catch {
            return []
        }
    }

    private func mealMessages(from meals: [LongevityAPI.Meal]) -> [ChatMessage] {
        meals.map { meal in
            ChatMessage(
                kind: .meal(MealCard(from: meal)),
                // Domknięcie, nie referencja: parseTimestamp ma domyślny
                // `fallback`, a Swift nie stosuje domyślnych argumentów przy
                // przekazywaniu funkcji jako wartości.
                at: meal.createdAt.map { ChatDates.parseTimestamp($0) } ?? Date()
            )
        }
    }

    // MARK: - Wysyłka tekstu

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }

        draft = ""
        append(.user(text))

        if let pending = pendingMeal {
            await clarifyMeal(pending, answer: text)
        } else if awaitingMealDescription {
            awaitingMealDescription = false
            await submitMeal(description: text, imageBase64: nil)
        } else {
            await ask(text)
        }
    }

    private func ask(_ question: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let reply = try await LongevityAPI.ask(question: question)
            append(.assistant(reply))
        } catch {
            append(.failure(error.localizedDescription))
        }
    }

    // MARK: - Posiłki

    func logMeal(photo: Data) async {
        guard !isBusy else { return }

        guard let base64 = MealPhoto.base64(from: photo) else {
            append(.failure("Nie udało się przygotować zdjęcia. Spróbuj innego."))
            return
        }

        awaitingMealDescription = false
        append(.confirmation("📷 Zdjęcie posiłku wysłane do analizy…"))
        await submitMeal(description: nil, imageBase64: base64)
    }

    /// Dymek użytkownika dokłada wołający — przy zdjęciu jest nim potwierdzenie,
    /// przy opisie tekst już wpisany w `send()`.
    private func submitMeal(description: String?, imageBase64: String?) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await LongevityAPI.logMeal(
                description: description,
                imageBase64: imageBase64
            )
            handleMealResult(result, imageBase64: imageBase64)
            await LongevityAPI.refreshScore()
        } catch {
            append(.failure(error.localizedDescription))
        }
    }

    private func clarifyMeal(_ pending: (id: String, imageBase64: String?), answer: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await LongevityAPI.clarifyMeal(
                id: pending.id,
                description: answer,
                imageBase64: pending.imageBase64
            )
            handleMealResult(result, imageBase64: pending.imageBase64)
            await LongevityAPI.refreshScore()
        } catch {
            append(.failure(error.localizedDescription))
        }
    }

    private func handleMealResult(_ result: LongevityAPI.MealReply, imageBase64: String?) {
        if result.meal.needsClarification, let question = result.question {
            pendingMeal = (id: result.meal.id, imageBase64: imageBase64)
            append(.assistant(question))
            return
        }

        pendingMeal = nil
        append(.meal(MealCard(from: result.meal)))
    }

    // MARK: - Aktywność

    /// Aktywność nie potrzebuje serwera — RLS pozwala zapisać własny wiersz,
    /// więc idzie wprost do Supabase. Score odświeżamy osobno.
    func logActivity(minutes: Int) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let userId = try await AppSupabase.client.auth.session.user.id.uuidString
            let payload = ActivityPayload(
                user_id: userId,
                logged_date: ChatDates.todayISO(),
                activity_minutes: minutes,
                source: "ios"
            )

            try await AppSupabase.client
                .from("activity_logs")
                .upsert(payload, onConflict: "user_id,logged_date")
                .execute()

            append(.confirmation("🏃 Aktywność zapisana: \(minutes) min"))
            await LongevityAPI.refreshScore()
        } catch {
            append(.failure(error.localizedDescription))
        }
    }

    // MARK: - Markery

    /// Uzupełnienie tego, czego HealthKit nie daje: VO2max rowerzysty, obwód
    /// bioder, odczyty przepisane z Garmina. Idzie przez serwer, bo to on
    /// pilnuje, żeby sync z zegarka tych pól nie nadpisał.
    func saveMarkers(_ markers: HealthMarkers) async {
        guard !isBusy, !markers.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await LongevityAPI.saveHealthMarkers(markers)
            append(.confirmation("📏 Zapisano: \(markers.summary)"))
            await LongevityAPI.refreshScore()
        } catch {
            append(.failure(error.localizedDescription))
        }
    }

    // MARK: - Check-in

    func saveCheckin(stress: Int, mood: Int) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await LongevityAPI.saveCheckin(stress: stress, mood: mood)
            append(.confirmation("✅ Check-in zapisany — stres \(stress)/5 • nastrój \(mood)/5"))
            await LongevityAPI.refreshScore()
        } catch {
            append(.failure(error.localizedDescription))
        }
    }

    // MARK: - Pomocnicze

    private func append(_ kind: ChatMessage.Kind) {
        messages.append(ChatMessage(kind: kind))
    }
}
