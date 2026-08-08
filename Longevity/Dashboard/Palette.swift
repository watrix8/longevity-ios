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
///
/// ## Co znaczy który kolor
///
/// Bez tej umowy jeden kolor niósł na raz cztery rzeczy: w Opcjach ochra
/// oznaczała jednocześnie wartość do wyboru, akcję, zwykłe dane i ostrzeżenie —
/// czyli nie oznaczała nic, bo nie dawała się przewidzieć.
///
/// - `pine` — **to można dotknąć** albo *jest dobrze*: akcje, linki, wartości
///   pod pickerem, „Połączono". Jedyny kolor, który obiecuje reakcję na dotyk.
/// - `ochre` / `ochreInk` — **na to patrz**: Twój wynik i to, co go liczy,
///   plus ostrzeżenia. Nigdy nie oznacza rzeczy klikalnej. Wyjątkiem jest
///   zaznaczenie zakładki w `RootTabView`, gdzie ochra jest znakiem marki,
///   a nie obietnicą akcji.
/// - `ink` → `muted` → `tick` — trzy poziomy tekstu, od treści do przypisu.
/// - `.red` — wyłącznie rzeczy nieodwracalne i błędy.
///
/// ## Warstwy
///
/// `paper` to tło strony, `card` to biel podniesionych bloków, `panel` to
/// wypełnienie WEWNĄTRZ karty (bieżnie pasków, tła wykresów, pigułki).
/// Wcześniej strona i karta miały ten sam biały kolor, więc karty rozpoznawało
/// się wyłącznie po obwódce o kontraście 1,32:1 — czyli praktycznie po niczym.
/// `panel` położony wprost na `paper` jest niewidoczny (1,07:1): co siedzi
/// na stronie, dostaje `card`, co siedzi w karcie — `panel`.
///
/// ## Kontrast
///
/// Wartości nie są dobrane na oko — każda przechodzi WCAG AA (4,5:1) na
/// wszystkich trzech tłach, na których faktycznie występuje. `ochre` została
/// przy 3,54:1, więc wolno jej nieść tylko duże liczby i wypełnienia; tekst
/// w rozmiarze zwykłym bierze `ochreInk` (5,64:1). Poprzednio `tick` miał
/// 2,60:1 i mimo tego nosił skalę „/100", podpisy osi i wagi procentowe.
enum Palette {
    /// Tło strony.
    static let paper = Color(hex: 0xE9EFE2)
    /// Podniesione bloki: karty, dymki, pola na stronie.
    static let card = Color(hex: 0xFFFFFF)
    /// Wypełnienie wewnątrz karty — na `paper` znika, nie kłaść go tam.
    static let panel = Color(hex: 0xF3F6EF)

    static let ink = Color(hex: 0x18211C)
    static let muted = Color(hex: 0x535A54)
    static let tick = Color(hex: 0x656E66)
    static let line = Color(hex: 0xCFD7C7)

    static let pine = Color(hex: 0x2F6B5E)
    static let pineSoft = Color(hex: 0xD6E6DF)

    /// Tylko duże liczby i wypełnienia — na tekst zwykłej wielkości `ochreInk`.
    static let ochre = Color(hex: 0xC5751D)
    static let ochreInk = Color(hex: 0x995710)
    /// Tło bloku ostrzeżenia. Działa na `card`, na `paper` jest niewidoczne.
    static let ochreSoft = Color(hex: 0xF4E4CB)
    /// Pasek składowej drugiego poziomu. Jaśniejszy od `ochre` celowo —
    /// wartość liczbowa stoi obok każdego paska, więc kolor nie musi jej nieść.
    static let stem = Color(hex: 0xDFB579)
}

/// Kroje z makiety ATLAS: Bricolage Grotesque na nagłówki i liczby, Hanken
/// Grotesk na tekst, Space Mono na etykiety i dane. Pliki leżą w
/// `Longevity/Resources/Fonts` i są wpisane do `UIAppFonts` w `project.yml` —
/// bez tego wpisu iOS ich nie rejestruje i `Font.custom` cicho spada na
/// systemowy krój, bez żadnego błędu.
///
/// Nazwy niżej to PostScript name z tabeli `name` każdego TTF-a, a nie nazwa
/// pliku ani rodziny. To po nich szuka `Font.custom`, i tylko one są pewne:
/// „Bricolage Grotesque ExtraBold" jest u ExtraBolda rodziną, a nie stylem.
///
/// `fixedSize:`, nie `size:` — `Font.custom(_:size:)` skalowałby się
/// z Dynamic Type, a ekrany stoją dziś na stałych szerokościach kolumn
/// (118/128/34 pt) i jednej cyfrze w 112 pt. Podmiana krojów ma nie ruszyć
/// układu; skalowanie tekstu to osobna robota razem z tymi szerokościami.
enum AtlasFont {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom(displayFace(weight), fixedSize: size)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(bodyFace(weight), fixedSize: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(monoFace(weight), fixedSize: size)
    }

    // MARK: - Wagi

    /// Bricolage nie ma statyki cięższej niż ExtraBold (800), więc `.heavy`
    /// i `.black` schodzą do niej zamiast prosić iOS o pogrubienie syntetyczne.
    private static func displayFace(_ weight: Font.Weight) -> String {
        switch weight {
        case .heavy, .black: "BricolageGrotesque-ExtraBold"
        case .semibold: "BricolageGrotesque-SemiBold"
        default: "BricolageGrotesque-Bold"
        }
    }

    private static func bodyFace(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "HankenGrotesk-Bold"
        case .semibold: "HankenGrotesk-SemiBold"
        case .medium: "HankenGrotesk-Medium"
        default: "HankenGrotesk-Regular"
        }
    }

    /// Space Mono ma tylko regular i bold — wszystko od semibolda w górę
    /// dostaje bold, bo pośredniej wagi nie ma z czego wziąć.
    private static func monoFace(_ weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: "SpaceMono-Bold"
        default: "SpaceMono-Regular"
        }
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
                    Palette.paper.frame(height: inset)
                    LinearGradient(
                        colors: [Palette.paper, Palette.paper.opacity(0)],
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
