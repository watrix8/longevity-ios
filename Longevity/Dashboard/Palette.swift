import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Paleta z makiety ATLAS. Wartości sztywne — ekran ma wyglądać tak samo
/// niezależnie od trybu jasny/ciemny.
enum Palette {
    static let ink = Color(hex: 0x18211C)
    static let card = Color(hex: 0xFFFFFF)
    static let panel = Color(hex: 0xF3F6EF)
    static let muted = Color(hex: 0x6A746C)
    static let line = Color(hex: 0xDCE2D6)
    static let pine = Color(hex: 0x2F6B5E)
    static let pineSoft = Color(hex: 0xD6E6DF)
    static let ochre = Color(hex: 0xC9781E)
    static let ochreInk = Color(hex: 0xA85F12)
    static let ochreSoft = Color(hex: 0xF4E4CB)
    static let stem = Color(hex: 0xE7C79A)
    static let tick = Color(hex: 0x9AA39B)
}

/// Odpowiedniki krojów z makiety (Bricolage Grotesque / Hanken Grotesk / Space Mono)
/// zbudowane na fontach systemowych — bez dociągania plików TTF.
enum AtlasFont {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Zasłania obszar statusu: zegarek, wifi i baterię.
    ///
    /// Ekrany nie mają paska nawigacji, więc iOS nie rysuje tam z automatu
    /// niczego, a przewijana treść przejeżdża wprost pod cyframi zegara.
    /// `scrollEdgeEffectStyle` z iOS 26 tego nie łapie — efekt krawędzi
    /// potrzebuje paska, do którego mógłby się przykleić. Zamiast tego pas
    /// w kolorze tła plus krótki gradient pod nim: tekst wygasza się,
    /// zamiast urywać w połowie wiersza.
    func statusBarCover(fade: CGFloat = 16) -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                // Wysokość paska statusu bierzemy z pomiaru, bo różni się
                // między modelami. Nakładka mieszka wewnątrz bezpiecznego
                // obszaru, więc dopiero `offset` wypycha ją nad jego krawędź —
                // samo `ignoresSafeArea` na tym poziomie nic nie rozciąga.
                let inset = proxy.safeAreaInsets.top
                VStack(spacing: 0) {
                    Palette.card.frame(height: inset)
                    LinearGradient(
                        colors: [Palette.card, Palette.card.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: fade)
                }
                .frame(maxWidth: .infinity)
                .offset(y: -inset)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Nagłówek zakładki: wersaliki, szeroki tracking, ochrowa kropka.
///
/// Jeden typ dla wszystkich czterech ekranów — wcześniej Dashboard i Asystent
/// niosły ten kształt inline, a Trendy i Opcje dryfowały we własny stopień
/// pisma bez kropki.
struct ScreenTitle: View {
    /// `LocalizedStringResource`, nie `String` — dzięki temu wywołanie z gołym
    /// tekstem trafia do String Catalogu, a wartość policzona w kodzie nie da
    /// się tu wstawić przez pomyłkę (nie skompiluje się).
    let text: LocalizedStringResource

    var body: some View {
        HStack(spacing: 0) {
            Text(String(localized: text).uppercased())
            Text(verbatim: ".").foregroundStyle(Palette.ochre)
        }
        .font(AtlasFont.display(15, .heavy))
        .tracking(2.1)
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Nagłówek sekcji: mono, wersaliki, szeroki tracking.
struct Kicker: View {
    private let text: String
    private let color: Color
    private let size: CGFloat

    init(text: LocalizedStringResource, color: Color = Palette.muted, size: CGFloat = 10) {
        self.init(verbatim: String(localized: text), color: color, size: size)
    }

    /// Dla nagłówków składanych w kodzie — są już w języku użytkownika
    /// i nie ma czego szukać w String Catalogu.
    init(verbatim text: String, color: Color = Palette.muted, size: CGFloat = 10) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(verbatim: text.uppercased())
            .font(AtlasFont.mono(size))
            .tracking(size * 0.16)
            .foregroundStyle(color)
    }
}
