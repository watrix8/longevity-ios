import Foundation

/// Ostatnio widziana rozmowa, zapisana lokalnie.
///
/// Wejście w zakładkę czekało na jedno zapytanie do Supabase — czterdzieści
/// wierszy to około 28 KB, czyli 200–400 ms po szybkim łączu i grubo ponad
/// sekundę w sieci komórkowej. Przez ten czas ekran zasłaniał kręciołek,
/// mimo że treść sprzed chwili leżała już na dysku.
///
/// Rozmowa pokazuje się więc od razu z dysku, a odpowiedź z serwera ją
/// podmienia. Trzymamy wyłącznie tury, które i tak przyszły z serwera —
/// zdjęcia posiłków i potwierdzenia zapisu żyją tylko w sesji.
enum ChatHistoryCache {
    private struct Snapshot: Codable {
        /// Bez tego po przelogowaniu pierwszy ekran pokazałby cudzą rozmowę.
        let userId: String
        let turns: [Turn]
    }

    private struct Turn: Codable {
        let role: String
        let content: String
        let at: Date
    }

    private static var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        return base.appending(path: "chat-history.json")
    }

    /// Zwraca pustą tablicę, gdy cache nie istnieje albo należy do kogoś innego.
    /// Każdy błąd odczytu jest równoważny brakowi cache'u — to tylko skrót,
    /// nie źródło prawdy.
    static func load(userId: String?) -> [ChatMessage] {
        guard let userId,
              let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.userId == userId
        else { return [] }

        return snapshot.turns.map { turn in
            ChatMessage(
                kind: turn.role == "user" ? .user(turn.content) : .assistant(turn.content),
                at: turn.at,
                id: ChatMessage.historyID(role: turn.role, at: turn.at)
            )
        }
    }

    static func save(_ messages: [ChatMessage], userId: String?) {
        guard let userId, let fileURL else { return }

        let turns: [Turn] = messages.compactMap { message in
            switch message.kind {
            case .user(let text): Turn(role: "user", content: text, at: message.at)
            case .assistant(let text): Turn(role: "assistant", content: text, at: message.at)
            // Zdjęcie, potwierdzenie i błąd nie mają odpowiednika po stronie
            // serwera, więc nie udajemy, że są częścią historii.
            case .photo, .confirmation, .failure: nil
            }
        }

        guard let data = try? JSONEncoder().encode(Snapshot(userId: userId, turns: turns)) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }

    /// Wołane przy wylogowaniu — inaczej plik przeżyłby zmianę konta i czekał
    /// na kogoś, kto zaloguje się tym samym identyfikatorem.
    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
