import Foundation
import UIKit

/// Jedna pozycja w feedzie czatu.
struct ChatMessage: Identifiable, Sendable {
    enum Kind: Sendable {
        case user(String)
        /// Zdjęcie posiłku z opcjonalnym komentarzem — to, co użytkownik
        /// wysłał. Żyje tylko w sesji: w historii zostaje sam tekst.
        case photo(Data, caption: String?)
        /// Markdown — dokładnie to, co wygenerował model.
        case assistant(String)
        /// Potwierdzenie zapisu (aktywność, check-in). Żyje tylko w sesji.
        case confirmation(String)
        case failure(String)
    }

    let id = UUID()
    /// Zmienny, bo dymek asystenta rośnie w trakcie strumienia.
    var kind: Kind
    let at: Date

    init(kind: Kind, at: Date = Date()) {
        self.kind = kind
        self.at = at
    }
}

enum ChatDates {
    /// Dzień liczony w strefie Warszawy, tak jak `getWarsawDateISO()` na backendzie —
    /// inaczej wpis zrobiony po 22:00 latem trafiłby na wczoraj.
    static func todayISO(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Warsaw")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    /// Postgres zwraca znaczniki raz z ułamkami sekund, raz bez.
    static func parseTimestamp(_ raw: String, fallback: Date = Date()) -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw) ?? fallback
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

        // Bez wymuszonej skali 1 renderer używa skali ekranu — na iPhonie 3×, więc
        // limit 1024 px dawałby w rzeczywistości 3072 px i dziewięciokrotnie
        // cięższy payload, niż zakłada `maxDimension`.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
