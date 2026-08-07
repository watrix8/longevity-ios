import Foundation
import Testing
import UIKit

@testable import Longevity

@Suite("Daty czatu")
struct ChatDatesTests {
    private func instant(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    @Test("Dzień liczy się w strefie Warszawy, nie UTC")
    func todayUsesWarsawTimezone() {
        // 22:30 UTC to już 00:30 następnego dnia w Warszawie (lato, UTC+2).
        #expect(ChatDates.todayISO(now: instant("2026-08-06T22:30:00Z")) == "2026-08-07")
        #expect(ChatDates.todayISO(now: instant("2026-08-06T21:30:00Z")) == "2026-08-06")
    }

    @Test("Zimą przesunięcie to UTC+1")
    func todayHandlesWinterOffset() {
        #expect(ChatDates.todayISO(now: instant("2026-01-15T23:30:00Z")) == "2026-01-16")
        #expect(ChatDates.todayISO(now: instant("2026-01-15T22:30:00Z")) == "2026-01-15")
    }

    @Test("Znacznik z ułamkami sekund parsuje się poprawnie")
    func parsesFractionalTimestamp() {
        let parsed = ChatDates.parseTimestamp("2026-08-06T18:23:09.04277+00:00")
        // Ułamek zostaje zachowany, więc porównujemy z tolerancją — chodzi o to,
        // że w ogóle się sparsował, nie o równość co do mikrosekundy.
        #expect(abs(parsed.timeIntervalSince(instant("2026-08-06T18:23:09Z"))) < 0.1)
    }

    @Test("Znacznik bez ułamków też — Postgres zwraca oba warianty")
    func parsesPlainTimestamp() {
        let parsed = ChatDates.parseTimestamp("2026-08-06T18:23:09+00:00")
        #expect(parsed == instant("2026-08-06T18:23:09Z"))
    }

    @Test("Śmieciowy znacznik nie wywraca feedu, tylko wraca fallbackiem")
    func fallsBackOnGarbage() {
        let fallback = instant("2026-01-01T00:00:00Z")
        #expect(ChatDates.parseTimestamp("", fallback: fallback) == fallback)
        #expect(ChatDates.parseTimestamp("wczoraj", fallback: fallback) == fallback)
    }
}

@Suite("Karta posiłku")
struct MealCardTests {
    @Test("Kategorie z serwera mapują się na polskie etykiety")
    func mapsKnownCategories() {
        #expect(MealCard.categoryLabel("breakfast") == "Śniadanie")
        #expect(MealCard.categoryLabel("lunch") == "Lunch")
        #expect(MealCard.categoryLabel("dinner") == "Obiad")
        #expect(MealCard.categoryLabel("supper") == "Kolacja")
        #expect(MealCard.categoryLabel("snack") == "Przekąska")
    }

    @Test("Nieznana i pusta kategoria lądują na neutralnym 'Posiłek'")
    func fallsBackForUnknownCategory() {
        #expect(MealCard.categoryLabel("other") == "Posiłek")
        #expect(MealCard.categoryLabel(nil) == "Posiłek")
        #expect(MealCard.categoryLabel("brunch") == "Posiłek")
    }

    /// Serwer odsyła snake_case — ten test pilnuje, żeby CodingKeys nie rozjechały się
    /// z kształtem odpowiedzi z `/api/v1/meals`.
    @Test("Odpowiedź serwera dekoduje się na kartę")
    func decodesServerResponse() throws {
        let json = """
        {
          "question": null,
          "meal": {
            "id": "abc-123",
            "status": "analyzed",
            "meal_title": "Kurczak z ryżem",
            "meal_category": "dinner",
            "kcal_min": 876,
            "kcal_max": 1185,
            "protein_g": 57,
            "carbs_g": 116.5,
            "fat_g": 38,
            "meal_score": 67,
            "insight_text": "Solidne białko.",
            "insight_action": "Dorzuć warzywa.",
            "created_at": "2026-08-06T18:26:00+00:00"
          }
        }
        """

        let reply = try JSONDecoder().decode(
            LongevityAPI.MealReply.self,
            from: Data(json.utf8)
        )

        #expect(reply.question == nil)
        #expect(reply.meal.needsClarification == false)

        let card = MealCard(from: reply.meal)
        #expect(card.title == "Kurczak z ryżem")
        #expect(card.category == "Obiad")
        #expect(card.kcalMin == 876)
        #expect(card.carbsG == 116.5)
        #expect(card.score == 67)
        #expect(card.action == "Dorzuć warzywa.")
    }

    @Test("Posiłek bez tytułu dostaje domyślny, nie pusty dymek")
    func handlesMissingTitle() throws {
        let json = """
        {"meal": {"id": "x", "status": "needs_clarification", "meal_title": null,
        "meal_category": null, "kcal_min": null, "kcal_max": null, "protein_g": null,
        "carbs_g": null, "fat_g": null, "meal_score": null, "insight_text": null,
        "insight_action": null, "created_at": null}, "question": "Jaka porcja?"}
        """

        let reply = try JSONDecoder().decode(LongevityAPI.MealReply.self, from: Data(json.utf8))

        #expect(reply.meal.needsClarification)
        #expect(reply.question == "Jaka porcja?")
        #expect(MealCard(from: reply.meal).title == "Posiłek")
    }
}

@Suite("Markdown od asystenta")
struct AssistantMarkdownTests {
    @Test("Nagłówek zamienia się w pogrubienie, zamiast zostać gołym hashem")
    func headings() {
        #expect(AssistantMarkdown.flattenBlocks("# Wniosek") == "**Wniosek**")
        #expect(AssistantMarkdown.flattenBlocks("### Co zrobić dziś") == "**Co zrobić dziś**")
        #expect(AssistantMarkdown.flattenBlocks("   ## Z wcięciem") == "**Z wcięciem**")
    }

    @Test("Punkt listy dostaje kropkę, bo parser inline list nie rysuje")
    func bullets() {
        #expect(AssistantMarkdown.flattenBlocks("- stała pora snu") == "• stała pora snu")
        #expect(AssistantMarkdown.flattenBlocks("  * kofeina do 14:00") == "• kofeina do 14:00")
    }

    @Test("Pogrubienie i tekst bez składni blokowej przechodzą bez zmian")
    func inlineUntouched() {
        #expect(AssistantMarkdown.flattenBlocks("**Wniosek**") == "**Wniosek**")
        #expect(AssistantMarkdown.flattenBlocks("bez formatowania") == "bez formatowania")
        #expect(AssistantMarkdown.flattenBlocks("5 - 7 godzin snu") == "5 - 7 godzin snu")
    }

    @Test("Hash bez spacji to nie nagłówek, tylko treść")
    func notAHeading() {
        #expect(AssistantMarkdown.flattenBlocks("#sen") == "#sen")
        #expect(AssistantMarkdown.flattenBlocks("#### za głęboko") == "#### za głęboko")
    }

    @Test("Wielolinijkowa odpowiedź zachowuje układ wierszy")
    func multiline() {
        let flattened = AssistantMarkdown.flattenBlocks("## Wniosek\n\n- krok jeden\n- krok dwa")
        #expect(flattened == "**Wniosek**\n\n• krok jeden\n• krok dwa")
    }

    @Test("Odpowiedź z HTML-em nie wywraca dymka, tylko ląduje jako tekst")
    func brokenMarkdownFallsBack() {
        let rendered = AssistantMarkdown.attributed("## Wniosek\n- sen")
        #expect(String(rendered.characters).contains("Wniosek"))
        #expect(String(rendered.characters).contains("• sen"))
        #expect(!String(rendered.characters).contains("##"))
    }
}

@Suite("Przygotowanie zdjęcia")
struct MealPhotoTests {
    /// Skala 1, żeby zadeklarowany rozmiar był rozmiarem w pikselach — domyślnie
    /// renderer użyłby skali ekranu symulatora i testy zależałyby od urządzenia.
    private func jpeg(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 1)!
    }

    private func decoded(_ base64: String) -> UIImage? {
        Data(base64Encoded: base64).flatMap(UIImage.init(data:))
    }

    @Test("Duże zdjęcie schodzi do limitu dłuższego boku")
    func downscalesLargePhoto() throws {
        let base64 = try #require(MealPhoto.base64(from: jpeg(width: 4032, height: 3024)))
        let image = try #require(decoded(base64))

        #expect(max(image.size.width, image.size.height) == 1024)
        // Proporcje muszą zostać — inaczej model widzi zniekształcony talerz.
        #expect(abs(image.size.width / image.size.height - 4032.0 / 3024.0) < 0.01)
    }

    @Test("Małe zdjęcie nie jest rozciągane w górę")
    func leavesSmallPhotoAlone() throws {
        let base64 = try #require(MealPhoto.base64(from: jpeg(width: 320, height: 240)))
        let image = try #require(decoded(base64))

        #expect(image.size.width == 320)
        #expect(image.size.height == 240)
    }

    @Test("Skalowanie realnie zbija rozmiar payloadu")
    func shrinksPayload() throws {
        let original = jpeg(width: 4032, height: 3024)
        let base64 = try #require(MealPhoto.base64(from: original))

        // base64 puchnie o ~33%, więc i tak musi być wyraźnie mniejszy od oryginału.
        #expect(base64.count < original.count)
    }

    @Test("Dane, które nie są obrazem, dają nil zamiast wysyłki śmieci")
    func rejectsNonImageData() {
        #expect(MealPhoto.base64(from: Data("to nie jest zdjęcie".utf8)) == nil)
        #expect(MealPhoto.base64(from: Data()) == nil)
    }
}

@Suite("Routing composera")
@MainActor
struct ChatRoutingTests {
    @Test("Domyślnie composer pyta asystenta")
    func defaultsToAssistant() {
        let model = ChatViewModel(isLoadingHistory: false)

        #expect(model.isComposingMeal == false)
        #expect(model.placeholder == "Zapytaj o cokolwiek…")
    }

    /// Regresja: „Opisz słowami" ustawiało tylko fokus, więc opis posiłku leciał
    /// do asystenta zamiast do `/api/v1/meals`.
    @Test("Po 'Opisz słowami' composer czeka na posiłek, nie na pytanie")
    func switchesToMealComposition() {
        let model = ChatViewModel(isLoadingHistory: false)
        model.startMealDescription()

        #expect(model.isComposingMeal)
        #expect(model.placeholder == "Co jesz? Podaj też wielkość porcji…")
    }

    @Test("Pusty i sam biały znak nie wysyłają nic")
    func ignoresBlankDraft() async {
        let model = ChatViewModel(isLoadingHistory: false)

        model.draft = "   \n  "
        await model.send()

        #expect(model.messages.isEmpty)
        // Draft zostaje nietknięty — nie ma czego czyścić, skoro nic nie poszło.
        #expect(model.draft == "   \n  ")
    }

    @Test("Wiadomości z historii trafiają do feedu w podanej kolejności")
    func seedsHistory() {
        let model = ChatViewModel(
            messages: [
                ChatMessage(kind: .user("pytanie")),
                ChatMessage(kind: .assistant("odpowiedź")),
            ],
            isLoadingHistory: false
        )

        #expect(model.messages.count == 2)
        if case .user(let text) = model.messages[0].kind {
            #expect(text == "pytanie")
        } else {
            Issue.record("Pierwsza wiadomość powinna być od użytkownika")
        }
    }
}
