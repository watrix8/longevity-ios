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

/// Nagłówek zakładki: wersaliki, szeroki tracking, ochrowa kropka.
///
/// Jeden typ dla wszystkich czterech ekranów — wcześniej Dashboard i Asystent
/// niosły ten kształt inline, a Trendy i Opcje dryfowały we własny stopień
/// pisma bez kropki.
struct ScreenTitle: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Text(text.uppercased())
            Text(".").foregroundStyle(Palette.ochre)
        }
        .font(AtlasFont.display(15, .heavy))
        .tracking(2.1)
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Nagłówek sekcji: mono, wersaliki, szeroki tracking.
struct Kicker: View {
    let text: String
    var color: Color = Palette.muted
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(AtlasFont.mono(size))
            .tracking(size * 0.16)
            .foregroundStyle(color)
    }
}
