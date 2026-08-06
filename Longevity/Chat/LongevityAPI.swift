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

    /// Podzbiór `meal_logs` + wyliczenia z `personalizeMealInsight`, które
    /// serwer dokłada do odpowiedzi.
    struct Meal: Decodable, Sendable {
        let id: String
        let status: String
        let mealTitle: String?
        let mealCategory: String?
        let kcalMin: Int?
        let kcalMax: Int?
        let proteinG: Double?
        let carbsG: Double?
        let fatG: Double?
        let mealScore: Int?
        let insightText: String?
        let insightAction: String?
        /// Brak przy odpowiedzi z PATCH-a, dlatego opcjonalne.
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, status
            case mealTitle = "meal_title"
            case mealCategory = "meal_category"
            case kcalMin = "kcal_min"
            case kcalMax = "kcal_max"
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
            case mealScore = "meal_score"
            case insightText = "insight_text"
            case insightAction = "insight_action"
            case createdAt = "created_at"
        }

        var needsClarification: Bool { status == "needs_clarification" }
    }

    struct MealReply: Decodable, Sendable {
        /// Dopytanie, gdy analiza jest niepewna — ta sama pętla co w bocie.
        let question: String?
        let meal: Meal
    }

    struct MealsToday: Decodable, Sendable {
        let meals: [Meal]
    }

    // MARK: - Wywołania

    static func ask(question: String) async throws -> String {
        let response: AssistantReply = try await send(
            "/api/v1/assistant",
            method: "POST",
            body: ["question": question, "source": "ios"]
        )
        return response.reply
    }

    /// Posiłki z dziś razem z meal score i insightem — te są liczone na serwerze,
    /// więc czytanie `meal_logs` wprost z Supabase dałoby same surowe makro.
    static func todaysMeals() async throws -> [Meal] {
        let response: MealsToday = try await send(
            "/api/v1/meals/today",
            method: "GET",
            body: Empty?.none
        )
        return response.meals
    }

    static func logMeal(description: String?, imageBase64: String?) async throws -> MealReply {
        var body: [String: String] = ["source": "ios"]
        if let description, !description.isEmpty { body["description"] = description }
        if let imageBase64 { body["image_base64"] = imageBase64 }

        return try await send("/api/v1/meals", method: "POST", body: body)
    }

    static func clarifyMeal(
        id: String,
        description: String,
        imageBase64: String?
    ) async throws -> MealReply {
        var body = ["description": description]
        if let imageBase64 { body["image_base64"] = imageBase64 }

        return try await send("/api/v1/meals/\(id)", method: "PATCH", body: body)
    }

    static func saveCheckin(sleep: Int, stress: Int, mood: Int) async throws {
        let _: Empty = try await send(
            "/api/v1/checkins/today",
            method: "PUT",
            body: [
                "sleep_quality": sleep,
                "stress_level": stress,
                "mood": mood,
            ]
        )
    }

    /// `GET /score/today` przelicza i zapisuje snapshot po drodze, więc to jest
    /// odświeżenie Longevity Score — nie tylko odczyt. Wołane po każdym zapisie.
    static func refreshScore() async {
        _ = try? await send("/api/v1/score/today", method: "GET", body: Empty?.none) as Empty
    }

    // MARK: - Transport

    private struct Empty: Codable, Sendable {}

    private struct ServerError: Decodable { let error: String? }

    private static func send<Body: Encodable, Response: Decodable>(
        _ path: String,
        method: String,
        body: Body
    ) async throws -> Response {
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
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            let parsed = try? JSONDecoder().decode(ServerError.self, from: data)
            throw Failure(message: parsed?.error ?? "Serwer odpowiedział błędem (\(status)).")
        }

        // Część wywołań interesuje nas tylko efektem ubocznym — pusta odpowiedź
        // nie jest wtedy błędem.
        if Response.self == Empty.self, let empty = Empty() as? Response { return empty }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Failure(message: "Nie udało się odczytać odpowiedzi serwera.")
        }
    }
}
