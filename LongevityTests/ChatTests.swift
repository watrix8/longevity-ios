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

@Suite("Markdown od asystenta")
struct AssistantMarkdownTests {
    @Test("Nagłówek staje się osobnym blokiem, nie gołym hashem w akapicie")
    func headings() {
        #expect(AssistantMarkdown.blocks("## Wniosek") == [.heading("Wniosek")])
        #expect(AssistantMarkdown.blocks("# Sen") == [.heading("Sen")])
        #expect(AssistantMarkdown.blocks("### Co zrobić dziś") == [.heading("Co zrobić dziś")])
    }

    @Test("Wiersz złożony z samego pogrubienia też jest nagłówkiem")
    func boldLineIsHeading() {
        #expect(AssistantMarkdown.blocks("**Wniosek**") == [.heading("Wniosek")])
    }

    @Test("Emoji z fallbacku regułowego zostaje w tytule sekcji")
    func ornamentedHeading() {
        #expect(AssistantMarkdown.blocks("✅ **Wniosek**") == [.heading("✅ Wniosek")])
    }

    @Test("Myślnik zamknięty w pogrubieniu nie zostaje sierotą w nagłówku")
    func headingWithStrayListMarker() {
        #expect(AssistantMarkdown.blocks("**- Niedziela: regeneracja**") == [.heading("Niedziela: regeneracja")])
        #expect(AssistantMarkdown.blocks("**• Sobota**") == [.heading("Sobota")])
        // Sam myślnik w pogrubieniu nie jest nagłówkiem po odjęciu markera.
        #expect(AssistantMarkdown.blocks("**- **") == [.paragraph("**- **")])
    }

    @Test("Zdanie z wyróżnieniem nie awansuje na nagłówek")
    func emphasisIsNotAHeading() {
        #expect(
            AssistantMarkdown.blocks("🧠 **Pytanie:** co z moim snem")
                == [.paragraph("🧠 **Pytanie:** co z moim snem")]
        )
        #expect(
            AssistantMarkdown.blocks("**Sen** wpływa na **stres**")
                == [.paragraph("**Sen** wpływa na **stres**")]
        )
    }

    @Test("Punkty listy stają się osobnymi blokami")
    func bullets() {
        #expect(
            AssistantMarkdown.blocks("- stała pora snu\n* kofeina do 14:00\n• bez ekranu")
                == [.bullet("stała pora snu"), .bullet("kofeina do 14:00"), .bullet("bez ekranu")]
        )
    }

    @Test("Numeracja zachowuje marker, bo '1)' i '1.' to nie to samo")
    func numbered() {
        #expect(
            AssistantMarkdown.blocks("1) Wniosek\n2. Dlaczego")
                == [.numbered(marker: "1)", text: "Wniosek"), .numbered(marker: "2.", text: "Dlaczego")]
        )
    }

    @Test("Myślnik w środku zdania nie robi z niego listy")
    func dashInsideSentence() {
        #expect(AssistantMarkdown.blocks("5 - 7 godzin snu") == [.paragraph("5 - 7 godzin snu")])
        #expect(AssistantMarkdown.blocks("#sen") == [.paragraph("#sen")])
    }

    @Test("Sąsiadujące wiersze sklejają się w akapit, pusta linia go zamyka")
    func paragraphs() {
        #expect(
            AssistantMarkdown.blocks("Pierwszy wiersz\ndrugi wiersz\n\nOsobny akapit")
                == [.paragraph("Pierwszy wiersz drugi wiersz"), .paragraph("Osobny akapit")]
        )
    }

    @Test("Pełna odpowiedź rozkłada się na sekcje, akapity i listę")
    func fullReply() {
        let markdown = """
            ## Wniosek
            Spałeś 8h 55m.

            ## Co zrobić dziś
            - stała pora snu
            - kofeina do 14:00
            """

        #expect(
            AssistantMarkdown.blocks(markdown) == [
                .heading("Wniosek"),
                .paragraph("Spałeś 8h 55m."),
                .heading("Co zrobić dziś"),
                .bullet("stała pora snu"),
                .bullet("kofeina do 14:00"),
            ]
        )
    }

    @Test("Pusty tekst nie tworzy pustych bloków")
    func empty() {
        #expect(AssistantMarkdown.blocks("") == [])
        #expect(AssistantMarkdown.blocks("\n\n   \n") == [])
    }

    @Test("Niedomknięte pogrubienie ze strumienia nie miga gwiazdkami")
    func partialEmphasis() {
        #expect(AssistantMarkdown.closingOpenEmphasis("Sen **jest wa") == "Sen jest wa")
        #expect(AssistantMarkdown.closingOpenEmphasis("Sen *jest") == "Sen jest")
        #expect(AssistantMarkdown.closingOpenEmphasis("Wartość `123") == "Wartość 123")
    }

    @Test("Domknięte pogrubienie zostaje nietknięte")
    func closedEmphasisSurvives() {
        #expect(AssistantMarkdown.closingOpenEmphasis("**Wniosek**") == "**Wniosek**")
        #expect(AssistantMarkdown.closingOpenEmphasis("bez formatowania") == "bez formatowania")
    }

    @Test("Składnia inline znika z wyrenderowanego tekstu")
    func inlineRendered() {
        let rendered = AssistantMarkdown.attributed("**Wniosek** i *kursywa*")
        #expect(String(rendered.characters) == "Wniosek i kursywa")
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
        #expect(model.placeholder == "Co jesz? Opisz krótko…")
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
