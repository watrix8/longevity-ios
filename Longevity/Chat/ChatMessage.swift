import Foundation
import UIKit

/// Karta posiłku po analizie — to, co bot wysyła jako wiadomość z makro i score.
struct MealCard: Sendable {
    let title: String
    let category: String
    let kcalMin: Int?
    let kcalMax: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let score: Int?
    let insight: String?
    let action: String?

    /// Etykiety 1:1 z `mealCategoryLabel()` w webhooku Telegrama.
    static func categoryLabel(_ raw: String?) -> String {
        switch raw {
        case "breakfast": "Śniadanie"
        case "lunch": "Lunch"
        case "dinner": "Obiad"
        case "supper": "Kolacja"
        case "snack": "Przekąska"
        default: "Posiłek"
        }
    }

    init(from meal: LongevityAPI.Meal) {
        title = meal.mealTitle ?? "Posiłek"
        category = Self.categoryLabel(meal.mealCategory)
        kcalMin = meal.kcalMin
        kcalMax = meal.kcalMax
        proteinG = meal.proteinG
        carbsG = meal.carbsG
        fatG = meal.fatG
        score = meal.mealScore
        insight = meal.insightText
        action = meal.insightAction
    }

    init(
        title: String,
        category: String,
        kcalMin: Int?,
        kcalMax: Int?,
        proteinG: Double?,
        carbsG: Double?,
        fatG: Double?,
        score: Int?,
        insight: String?,
        action: String?
    ) {
        self.title = title
        self.category = category
        self.kcalMin = kcalMin
        self.kcalMax = kcalMax
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.score = score
        self.insight = insight
        self.action = action
    }
}

/// Jedna pozycja w feedzie czatu.
struct ChatMessage: Identifiable, Sendable {
    enum Kind: Sendable {
        case user(String)
        /// Markdown — serwer konwertuje HTML-a spod Telegrama zanim odeśle.
        case assistant(String)
        case meal(MealCard)
        /// Potwierdzenie zapisu (aktywność, check-in). Żyje tylko w sesji.
        case confirmation(String)
        case failure(String)
    }

    let id = UUID()
    let kind: Kind
    let at: Date

    init(kind: Kind, at: Date = Date()) {
        self.kind = kind
        self.at = at
    }
}

enum MealPhoto {
    /// Zdjęcie z aparatu ma kilkanaście megapikseli. Model widzenia i tak nie
    /// potrzebuje więcej niż ~1024 px, a base64 z pełnej rozdzielczości
    /// przekroczyłby limit body na Vercelu.
    static func base64(from data: Data, maxDimension: CGFloat = 1024) -> String? {
        guard let image = UIImage(data: data) else { return nil }

        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
