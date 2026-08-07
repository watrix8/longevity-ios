import Foundation
import Observation

/// Wiersz `assistant_messages` — historia rozmowy z asystentem.
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

    /// Ustawiane przez „Opisz słowami" — bez tego opis posiłku poleciałby do
    /// asystenta jako zwykłe pytanie.
    private var awaitingMealDescription = false

    var isComposingMeal: Bool { awaitingMealDescription }

    var placeholder: String {
        awaitingMealDescription ? "Co jesz? Opisz krótko…" : "Zapytaj o cokolwiek…"
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

        messages = await loadConversation()
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

    // MARK: - Wysyłka tekstu

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }

        draft = ""
        append(.user(text))

        if awaitingMealDescription {
            awaitingMealDescription = false
            await streamMealAdvice(description: text, imageBase64: nil)
        } else {
            await ask(text)
        }
    }

    private func ask(_ question: String) async {
        await consume(LongevityAPI.askStream(question: question), whenEmpty: "Asystent nie odpowiedział. Spróbuj ponownie.")
    }

    // MARK: - Posiłki

    /// Posiłku nie zapisujemy — pytamy o niego model i pokazujemy odpowiedź.
    ///
    /// Wcześniej zdjęcie wracało kartą z kaloriami i makro, a przy niepewnej
    /// analizie pytaniem o wielkość porcji. Dziennik i tak nigdy nie był pełny,
    /// więc te liczby udawały pomiar. Teraz to zwykła rozmowa o jedzeniu.
    func adviseMeal(photo: Data) async {
        guard !isBusy else { return }

        guard let base64 = MealPhoto.base64(from: photo) else {
            append(.failure("Nie udało się przygotować zdjęcia. Spróbuj innego."))
            return
        }

        awaitingMealDescription = false
        append(.confirmation("📷 Zdjęcie wysłane do oceny…"))
        await streamMealAdvice(description: nil, imageBase64: base64)
    }

    /// Dymek użytkownika dokłada wołający — przy zdjęciu jest nim potwierdzenie,
    /// przy opisie tekst już wpisany w `send()`.
    private func streamMealAdvice(description: String?, imageBase64: String?) async {
        await consume(
            LongevityAPI.mealAdviceStream(description: description, imageBase64: imageBase64),
            whenEmpty: "Nie udało się ocenić tego posiłku. Spróbuj ponownie."
        )
    }

    /// Skleja kawałki w jeden rosnący dymek asystenta.
    ///
    /// Wspólne dla pytań i dla oceny posiłku — z punktu widzenia feedu to ta
    /// sama rzecz: odpowiedź modelu, która pisze się na oczach użytkownika.
    private func consume(
        _ stream: AsyncThrowingStream<String, Error>,
        whenEmpty emptyMessage: String
    ) async {
        isBusy = true
        defer { isBusy = false }

        var bubble: Int?
        var reply = ""

        do {
            for try await chunk in stream {
                reply += chunk

                if let index = bubble {
                    messages[index].kind = .assistant(reply)
                } else {
                    // Dymek zakładamy dopiero przy pierwszym znaku — pusta
                    // ramka czekająca na model wygląda jak usterka.
                    append(.assistant(reply))
                    bubble = messages.count - 1
                }
            }

            if reply.isEmpty { append(.failure(emptyMessage)) }
        } catch {
            // To, co zdążyło dojść, zostaje na ekranie — kasowanie połowy
            // odpowiedzi byłoby gorsze niż przyznanie się do urwania.
            append(.failure(
                bubble == nil
                    ? error.localizedDescription
                    : "Połączenie przerwane — odpowiedź może być niepełna."
            ))
        }
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
