import Foundation

/// Klient REST API z repo webowego.
///
/// Używamy go wyłącznie tam, gdzie logika musi zostać na serwerze: asystent
/// i analiza posiłków wołają Vercel AI Gateway kluczem, którego apka trzymać
/// nie może. Wszystko inne (score, aktywność, waga) idzie wprost do Supabase
/// pod RLS — tak jak Dashboard.
enum LongevityAPI {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Odpowiedzi

    struct AssistantReply: Decodable, Sendable {
        let reply: String
    }

    /// Liczniki z `/health/sync`. `activitySynced` i `weightSynced` bywają
    /// mniejsze od `saved` — serwer pomija dni, w których jest wpis ręczny.
    struct HealthSyncResult: Decodable, Sendable {
        let saved: Int
        let activitySynced: Int
        let weightSynced: Int

        enum CodingKeys: String, CodingKey {
            case saved
            case activitySynced = "activity_synced"
            case weightSynced = "weight_synced"
        }
    }

    // MARK: - Wywołania

    /// Język, w którym ma odpowiadać asystent — kod ISO („pl", „en").
    ///
    /// Interfejs tłumaczy String Catalog, ale treść od modelu układa serwer
    /// i sam z siebie nie wie, na jaki język przełączony jest telefon.
    /// Serwer, który tego pola nie obsługuje, po prostu je zignoruje.
    static var language: String {
        Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "pl"
    }

    static func ask(question: String) async throws -> String {
        let response: AssistantReply = try await send(
            "/api/v1/assistant",
            method: "POST",
            body: ["question": question, "source": "ios", "language": language]
        )
        return response.reply
    }

    private struct AskStreamBody: Encodable {
        let question: String
        let source = "ios"
        let stream = true
        let language = LongevityAPI.language
    }

    /// Zdarzenie SSE z `/api/v1/assistant`. Serwer emituje własny format,
    /// nie surowy strumień dostawcy — stąd te trzy pola i nic więcej.
    private struct StreamEvent: Decodable {
        let delta: String?
        let done: Bool?
        let error: String?
    }

    /// Odpowiedź asystenta kawałkami.
    ///
    /// Model potrafi pisać kilkanaście sekund, a pojedynczy kręciołek przez
    /// ten czas wygląda jak zawieszona apka. Kawałki lecą tak, jak schodzą
    /// z serwera — sklejanie ich w całość należy do wołającego.
    static func askStream(question: String) -> AsyncThrowingStream<String, Error> {
        streamSSE(path: "/api/v1/assistant") {
            try JSONEncoder().encode(AskStreamBody(question: question))
        }
    }

    /// Wspólny transport dla odpowiedzi strumieniowych: asystenta i oceny posiłku.
    private static func streamSSE(
        path: String,
        body: @escaping @Sendable () throws -> Data
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try await authorizedRequest(path: path, method: "POST")
                    // Model bywa powolniejszy niż zwykłe zapytanie, a przy
                    // strumieniu limit dotyczy przerwy między kawałkami.
                    request.timeoutInterval = 120
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try body()

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0

                    guard (200..<300).contains(status) else {
                        throw Failure(message: try await errorMessage(from: bytes, status: status))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }

                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty,
                              let event = try? JSONDecoder().decode(
                                  StreamEvent.self,
                                  from: Data(payload.utf8)
                              )
                        else { continue }

                        if let message = event.error { throw Failure(message: message) }
                        if let delta = event.delta { continuation.yield(delta) }
                        if event.done == true { break }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Zamknięcie ekranu w trakcie odpowiedzi ma ubić połączenie,
            // a nie zostawić je dociągające dane w tle.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Błąd przy strumieniu przychodzi zwykłym JSON-em, zanim zacznie się SSE.
    private static func errorMessage(from bytes: URLSession.AsyncBytes, status: Int) async throws -> String {
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count > 4096 { break }
        }

        let parsed = try? JSONDecoder().decode(ServerError.self, from: body)
        return parsed?.error ?? String(localized: "Serwer odpowiedział błędem (\(status)).")
    }

    private struct MealAdviceBody: Encodable {
        let description: String?
        let image_base64: String?
        let language = LongevityAPI.language
    }

    /// Opinia o posiłku, nie wpis do dziennika.
    ///
    /// Serwer nie liczy makro i nie odbija pytania o wielkość porcji — oddaje
    /// komentarz strumieniem, tak samo jak asystent odpowiada na pytania.
    static func mealAdviceStream(
        description: String?,
        imageBase64: String?
    ) -> AsyncThrowingStream<String, Error> {
        streamSSE(path: "/api/v1/meals/advice") {
            try JSONEncoder().encode(
                MealAdviceBody(
                    description: (description?.isEmpty ?? true) ? nil : description,
                    image_base64: imageBase64
                )
            )
        }
    }

    /// Bez `sleep_quality` — apka o sen nie pyta. Serwer wyprowadza ocenę
    /// z godzin zmierzonych przez Watcha, bo kolumna jest NOT NULL i karmi NBA.
    static func saveCheckin(stress: Int, mood: Int) async throws {
        let _: Empty = try await send(
            "/api/v1/checkins/today",
            method: "PUT",
            body: [
                "stress_level": stress,
                "mood": mood,
            ]
        )
    }

    /// Dane z HealthKit. Idą przez serwer, a nie wprost do Supabase, bo poza
    /// zapisem `health_metrics` trzeba jeszcze rozstrzygnąć priorytet źródeł
    /// przy przepisywaniu aktywności i wagi (ręczny wpis wygrywa z zegarkiem).
    static func syncHealth(days: [DailyHealthMetrics]) async throws -> HealthSyncResult {
        try await send("/api/v1/health/sync", method: "POST", body: HealthSyncPayload(days: days))
    }

    /// Wpis ręczny z czatu. Serwer dopisuje podane pola do `manual_fields`,
    /// przez co kolejny sync z zegarka ich nie ruszy.
    static func saveHealthMarkers(_ markers: HealthMarkers) async throws {
        let _: Empty = try await send("/api/v1/health/sync", method: "PATCH", body: markers)
    }

    /// `GET /score/today` przelicza i zapisuje snapshot po drodze, więc to jest
    /// odświeżenie Longevity Score — nie tylko odczyt. Wołane po każdym zapisie.
    static func refreshScore() async {
        _ = try? await send("/api/v1/score/today", method: "GET", body: Empty?.none) as Empty
    }

    // MARK: - Transport

    private struct Empty: Codable, Sendable {}

    private struct HealthSyncPayload: Encodable {
        let days: [DailyHealthMetrics]
    }

    private struct ServerError: Decodable { let error: String? }

    /// Adres, metoda i token — wspólne dla zapytań zwykłych i strumieniowych.
    private static func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        // `appending(path:)` traktuje argument jako względny, więc wiodący ukośnik
        // musi zniknąć — inaczej dostajemy podwójny w środku adresu.
        let url = AppSupabase.webBaseURL.appending(path: path.trimmingPrefix("/"))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60

        let token = try await AppSupabase.client.auth.session.accessToken
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private static func send<Body: Encodable, Response: Decodable>(
        _ path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        var request = try await authorizedRequest(path: path, method: method)

        if method != "GET" {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            let parsed = try? JSONDecoder().decode(ServerError.self, from: data)
            throw Failure(message: parsed?.error ?? String(localized: "Serwer odpowiedział błędem (\(status))."))
        }

        // Część wywołań interesuje nas tylko efektem ubocznym — pusta odpowiedź
        // nie jest wtedy błędem.
        if Response.self == Empty.self, let empty = Empty() as? Response { return empty }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Failure(message: String(localized: "Nie udało się odczytać odpowiedzi serwera."))
        }
    }
}
