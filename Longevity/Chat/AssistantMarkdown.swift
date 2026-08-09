import SwiftUI

/// Jeden blok odpowiedzi asystenta.
///
/// `AttributedString` czyta wyłącznie składnię inline, więc dopóki cała
/// odpowiedź szła jednym `Text`, nagłówki i listy nie miały jak dostać
/// odstępów ani wcięcia — wszystko lądowało w jednym ciągu akapitowym.
enum AssistantBlock: Equatable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
    /// Marker zostaje taki, jak napisał go model — „1)" i „1." to nie to samo.
    case numbered(marker: String, text: String)
}

enum AssistantMarkdown {
    // MARK: - Parsowanie

    /// Dzieli odpowiedź na bloki.
    ///
    /// Rozpoznaje trzy formaty naraz, bo w historii siedzą wszystkie: nagłówki
    /// `##` z bieżącego promptu, sekcje `1) Wniosek` sprzed zmiany formatu
    /// i wiersze `✅ **Wniosek**` z fallbacku regułowego.
    static func blocks(_ markdown: String) -> [AssistantBlock] {
        var blocks: [AssistantBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let title = headingTitle(line) {
                flushParagraph()
                blocks.append(.heading(title))
            } else if let text = bulletText(line) {
                flushParagraph()
                blocks.append(.bullet(text))
            } else if let (marker, text) = numberedItem(line) {
                flushParagraph()
                blocks.append(.numbered(marker: marker, text: text))
            } else {
                // Kolejne wiersze bez pustej linii to jeden akapit — tak działa
                // Markdown, a modele lubią łamać zdania w połowie.
                paragraph.append(line)
            }
        }

        flushParagraph()
        return blocks
    }

    /// `## Wniosek` albo wiersz złożony wyłącznie z pogrubienia, z opcjonalnym
    /// emoji z przodu (`✅ **Wniosek**`). Emoji zostaje w tytule.
    private static func headingTitle(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        // Spacja po hashu jest obowiązkowa — bez niej `#sen` to hasztag, nie sekcja.
        if (1...3).contains(hashes.count), line.dropFirst(hashes.count).first == " " {
            let title = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }

        let ornament = line.prefix { !$0.isLetter && !$0.isNumber && $0 != "*" }
        let rest = line.dropFirst(ornament.count)

        guard rest.hasPrefix("**"), rest.hasSuffix("**"), rest.count > 4 else { return nil }

        let inner = rest.dropFirst(2).dropLast(2)
        // Dwa pogrubienia w wierszu to zdanie z wyróżnieniami, nie nagłówek.
        guard !inner.isEmpty, !inner.contains("**") else { return nil }

        // Model bywa niekonsekwentny i pisze `**- Niedziela**`, mieszając
        // punkt listy z nagłówkiem. Myślnik zamknięty w pogrubieniu zostałby
        // na ekranie jako sierota, bo nie przechodzi ścieżką listy.
        var title = Substring(inner)
        for marker in ["- ", "* ", "• "] where title.hasPrefix(marker) {
            title = title.dropFirst(marker.count)
            break
        }
        guard !title.isEmpty else { return nil }

        let prefix = ornament.trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? String(title) : "\(prefix) \(title)"
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            let text = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> (String, String)? {
        let digits = line.prefix { $0.isNumber }
        guard (1...2).contains(digits.count) else { return nil }

        let rest = line.dropFirst(digits.count)
        guard let separator = rest.first, separator == ")" || separator == "." else { return nil }
        guard rest.dropFirst().first == " " else { return nil }

        let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : ("\(digits)\(separator)", text)
    }

    // MARK: - Render inline

    /// Ucina niedomknięte wyróżnienie na końcu tekstu.
    ///
    /// W trakcie strumienia `**Wnios` dociera bez zamknięcia i parser inline
    /// zostawiłby na ekranie gołe gwiazdki, które znikają dopiero przy
    /// następnym kawałku. Zamiast migotania wolimy chwilę zwykłego tekstu.
    static func closingOpenEmphasis(_ text: String) -> String {
        var result = text

        for token in ["**", "`", "*"] {
            let count = result.components(separatedBy: token).count - 1
            guard count % 2 == 1, let range = result.range(of: token, options: .backwards) else {
                continue
            }
            result.removeSubrange(range)
        }

        return result
    }

    /// Nieparsowalny Markdown ląduje w dymku jako czysty tekst — lepsze to
    /// niż pusta odpowiedź.
    static func attributed(_ text: String) -> AttributedString {
        let cleaned = closingOpenEmphasis(text)
        return (try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(cleaned)
    }
}

/// Trzy pulsujące kropki w miejscu, gdzie zaraz pojawi się odpowiedź.
///
/// Kręciołek w nagłówku ekranu mówił, że coś się dzieje, ale nie mówił gdzie —
/// w czacie oczekiwanie należy do rozmowy, nie do paska tytułu. Dymek stoi
/// tam, gdzie za chwilę stanie tekst, więc odpowiedź nie „wskakuje" znikąd.
struct TypingBubble: View {
    @State private var pulsing = false

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Palette.tick)
                        .frame(width: 7, height: 7)
                        .opacity(pulsing ? 1 : 0.3)
                        .scaleEffect(pulsing ? 1 : 0.72)
                        // Opóźnienie na kropkę robi falę zamiast mrugania
                        // trzema naraz.
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.18),
                            value: pulsing
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))

            Spacer(minLength: 40)
        }
        .onAppear { pulsing = true }
        .accessibilityLabel(Text("Asystent pisze odpowiedź"))
    }
}

/// Odpowiedź asystenta złożona z bloków — każdy z własnym odstępem
/// i, przy listach, wcięciem wiszącym.
///
/// `Equatable` nie jest ozdobą: feed rysuje się zachłannie, więc bez tego
/// każdy kawałek strumienia przeliczałby Markdown wszystkich dymków
/// w rozmowie, a nie tylko tego, który właśnie rośnie.
struct AssistantMarkdownView: View, Equatable {
    let markdown: String

    private var blocks: [AssistantBlock] { AssistantMarkdown.blocks(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .padding(.top, index == 0 ? 0 : spacingAbove(block))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nagłówek potrzebuje wyraźnie więcej powietrza nad sobą niż kolejny
    /// punkt listy — inaczej sekcje zlewają się w jeden blok tekstu.
    private func spacingAbove(_ block: AssistantBlock) -> CGFloat {
        switch block {
        case .heading: 16
        case .paragraph: 9
        case .bullet, .numbered: 5
        }
    }

    @ViewBuilder
    private func view(for block: AssistantBlock) -> some View {
        switch block {
        case .heading(let title):
            Text(AssistantMarkdown.attributed(title))
                .font(AtlasFont.body(14.5, .semibold))
                .foregroundStyle(Palette.ink)

        case .paragraph(let text):
            Text(AssistantMarkdown.attributed(text))
                .font(AtlasFont.body(14.5))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)

        case .bullet(let text):
            listRow(marker: "•", markerWidth: 12, text: text)

        case .numbered(let marker, let text):
            listRow(marker: marker, markerWidth: 20, text: text)
        }
    }

    /// `firstTextBaseline` trzyma marker w linii z pierwszym wierszem tekstu,
    /// a stała szerokość kolumny daje wcięcie wiszące przy zawijaniu.
    private func listRow(marker: String, markerWidth: CGFloat, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .font(AtlasFont.body(14.5))
                .monospacedDigit()
                .foregroundStyle(Palette.pine)
                .frame(width: markerWidth, alignment: .leading)

            Text(AssistantMarkdown.attributed(text))
                .font(AtlasFont.body(14.5))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
