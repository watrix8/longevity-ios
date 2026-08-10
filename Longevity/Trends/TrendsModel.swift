import Foundation
import Observation

struct SeriesPoint: Sendable, Equatable {
    let date: String
    let value: Double
}

/// Szerokość okna widocznego na Trendach.
///
/// Maksimum to kwartał i to jest decyzja, nie ograniczenie techniczne: przy
/// dłuższym oknie punkty robią się gęstsze niż piksele, więc trzeba by je
/// uśredniać — a wtedy wykres przestaje pokazywać konkretne dni. Zamiast tego
/// okno jest wąskie i PRZESUWALNE w przeszłość.
enum TrendWindow: String, CaseIterable, Identifiable, Sendable {
    case month, quarter

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .month: 30
        case .quarter: 90
        }
    }

    var label: String {
        switch self {
        case .month: String(localized: "30 dni")
        case .quarter: String(localized: "3 miesiące")
        }
    }
}

/// Widoczne okno jako daty ISO.
///
/// Wykres rozstawia punkty po dniach, więc musi znać granice okna — także
/// te dni, w których nic nie zmierzono. Bez tego pomiar co tydzień rysował
/// się identycznie jak pomiar co dzień.
struct DaySpan: Equatable, Sendable {
    let from: String
    let to: String

    /// Długość okna w dniach, obie granice włącznie.
    var days: Int {
        guard let start = CalendarDays.date(fromISO: from),
              let end = CalendarDays.date(fromISO: to)
        else { return 1 }
        return max(1, CalendarDays.days(from: start, to: end) + 1)
    }

    /// Pozycja dnia w oknie, 0...1. Poza oknem przycięta do krawędzi.
    func fraction(of iso: String) -> Double {
        guard days > 1,
              let start = CalendarDays.date(fromISO: from),
              let day = CalendarDays.date(fromISO: iso)
        else { return 0 }

        let offset = Double(CalendarDays.days(from: start, to: day))
        return min(max(offset / Double(days - 1), 0), 1)
    }
}

/// Skąd metryka bierze się w score. Kafelek bez tej informacji wygląda tak
/// samo ważnie jak ten, który realnie waży 30% wyniku.
enum MetricRole: Sendable, Equatable {
    /// Wchodzi do komponentu score'u — etykieta komponentu i jego waga.
    case feeds(component: String, weight: Double)
    /// Nie wchodzi do wyniku, ale opisuje dzień.
    case informational
    /// Sam wynik — nie jest ani składnikiem, ani metryką poboczną.
    case total

    /// Klucz sekcji. Metryki tej samej roli lądują razem, w kolejności
    /// pierwszego wystąpienia na liście.
    var groupID: String {
        switch self {
        case .feeds(let component, _): component
        case .informational: "informational"
        case .total: "total"
        }
    }

    var groupTitle: String {
        switch self {
        case .feeds(let component, _): component
        case .informational: String(localized: "Poza wynikiem")
        case .total: String(localized: "Wynik")
        }
    }

    var groupWeight: Double? {
        if case .feeds(_, let weight) = self { return weight }
        return nil
    }
}

/// Sekcja Trendów. Odpowiada jednemu komponentowi score'u, żeby kolejność
/// i podział na ekranie zgadzały się z rozbiciem na dashboardzie.
struct MetricGroup: Identifiable, Sendable {
    let id: String
    let title: String
    /// Udział komponentu w wyniku. `nil` dla sekcji spoza score'u.
    let weight: Double?
    let metrics: [Metric]

    var header: String {
        guard let weight else { return title }
        return "\(title) · \(Int((weight * 100).rounded()))%"
    }
}

/// Jak wartość punktu zamienia się w tekst na karcie.
///
/// Sen jest jedyną metryką, której jednostka nie jest dziesiętna: „8,6 h" każe
/// mnożyć w pamięci przez 60, żeby dowiedzieć się, że to 8 godzin i 36 minut.
/// Zegarek pokazuje tę wartość w godzinach i minutach i karta robi tak samo.
enum MetricFormat: Sendable {
    case decimal
    /// Wartość w godzinach, pokazywana jako godziny i minuty.
    case duration

    /// Zaokrąglenie do rozdzielczości, w jakiej wartość i tak się pokaże —
    /// bez niego średnia niosłaby dokładność, której karta nie wyświetla.
    func rounded(_ value: Double) -> Double {
        switch self {
        case .decimal: (value * 10).rounded() / 10
        case .duration: (value * 60).rounded() / 60
        }
    }

    func text(_ value: Double) -> String {
        switch self {
        case .decimal:
            // Bez zbędnego „.0" na całkowitych wartościach.
            return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        case .duration:
            // „h" i „min" są takie same po polsku i po angielsku, więc jednostki
            // zostają w kodzie, a nie w katalogu tłumaczeń.
            let minutes = Int((value * 60).rounded())
            let (hours, rest) = (minutes / 60, minutes % 60)
            if hours == 0 { return "\(rest)min" }
            if rest == 0 { return "\(hours)h" }
            return "\(hours)h \(rest)min"
        }
    }
}

/// Jedna karta metryki — odpowiednik `MetricCard` z `app/trends/page.tsx`.
struct Metric: Identifiable, Sendable {
    let id: String
    let title: String
    let unit: String
    /// Rosnąco po dacie.
    let points: [SeriesPoint]
    /// Czy wyższa wartość jest lepsza (waga, WHR i tętno spoczynkowe odwrotnie).
    let positiveHigher: Bool
    let role: MetricRole
    let format: MetricFormat

    var last: Double? { points.last?.value }
    var previous: Double? { points.dropLast().last?.value }
    /// Średnia CAŁEGO szeregu, nie trzydziestu dni — przy dłuższym zakresie
    /// obejmuje wszystko, co widać na wykresie.
    var avgAll: Double? { Self.average(points.map(\.value), format: format) }

    /// Wartość gotowa na kartę — z jednostką, jeśli format ją niesie.
    func text(_ value: Double) -> String { format.text(value) }

    /// Czy szereg przekracza granicę roku. Wtedy „08-06" przestaje wystarczać,
    /// bo nie wiadomo, o który rok chodzi.
    var spansYears: Bool {
        guard let first = points.first?.date.prefix(4), let last = points.last?.date.prefix(4)
        else { return false }
        return first != last
    }

    /// Opis punktu pod przeciągniętym palcem.
    ///
    /// Rok dochodzi, gdy punkt nie jest z bieżącego roku — tak samo, jak pisze
    /// się daty po polsku.
    func pointLabel(_ iso: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = try? Date("\(iso)T12:00:00Z", strategy: .iso8601) else { return iso }

        let polish = Locale.autoupdatingCurrent
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)

        var text = date.formatted(.dateTime.locale(polish).day().month(.wide))
        if !sameYear {
            text += " " + date.formatted(.dateTime.locale(polish).year())
        }
        return text
    }

    /// Etykieta osi. Przy szeregu przekraczającym rok miesiąc z rokiem, bo
    /// „07-08" w takim zakresie jest nieczytelne.
    func axisLabel(_ iso: String) -> String {
        spansYears ? String(iso.prefix(7)) : String(iso.suffix(5))
    }

    /// Strzałka jak w webie: porównanie z poprzednim punktem, odwrócona
    /// dla metryk, w których mniej znaczy lepiej.
    var arrow: String { arrow(at: points.indices.last) }

    /// Kierunek dla dowolnego dnia — przy przeciąganiu po wykresie strzałka ma
    /// opisywać wskazany punkt, a nie w kółko ostatni.
    func arrow(at index: Int?) -> String {
        guard let index, points.indices.contains(index), index > 0 else { return "→" }
        let current = points[index].value
        let earlier = points[index - 1].value
        let raw = current > earlier ? "↗" : (current < earlier ? "↘" : "→")
        guard !positiveHigher else { return raw }
        return raw == "↗" ? "↘" : (raw == "↘" ? "↗" : "→")
    }

    private static func average(_ values: [Double], format: MetricFormat) -> Double? {
        guard !values.isEmpty else { return nil }
        return format.rounded(values.reduce(0, +) / Double(values.count))
    }

}

// MARK: - Wiersze z Supabase

private struct ScoreRow: Decodable {
    let scoreDate: String
    let scoreTotal: Double
    /// Potrzebne dla składowych, które nie mają własnej kolumny w bazie —
    /// rozrzut długości snu liczy serwer przy score i tylko tu go widać.
    let components: ScoreComponents?

    enum CodingKeys: String, CodingKey {
        case scoreDate = "score_date", scoreTotal = "score_total", components
    }
}

private struct WeightRow: Decodable {
    let measuredAt: String
    let weightKg: Double
    enum CodingKeys: String, CodingKey {
        case measuredAt = "measured_at", weightKg = "weight_kg"
    }
}


private struct ActivityRow: Decodable {
    let loggedDate: String
    let activityMinutes: Double
    enum CodingKeys: String, CodingKey {
        case loggedDate = "logged_date", activityMinutes = "activity_minutes"
    }
}

/// Podzbiór `health_metrics` potrzebny na wykresy. Reszta kolumn (fazy snu poza
/// deep, SpO2, temperatura) jest w bazie, ale na razie nie ma własnego kafelka.
private struct HealthRow: Decodable {
    let metricDate: String
    let sleepAsleepMinutes: Int?
    let sleepDeepMinutes: Int?
    let sleepRegularityIndex: Double?
    let exerciseMinutes: Int?
    let vo2max: Double?
    let restingHeartRate: Double?
    let hrvSdnnMs: Double?
    let steps: Int?
    let bodyFatPct: Double?
    let waistCm: Double?
    let hipCm: Double?

    enum CodingKeys: String, CodingKey {
        case metricDate = "metric_date"
        case sleepAsleepMinutes = "sleep_asleep_minutes"
        case sleepDeepMinutes = "sleep_deep_minutes"
        case sleepRegularityIndex = "sleep_regularity_index"
        case exerciseMinutes = "exercise_minutes"
        case vo2max
        case restingHeartRate = "resting_heart_rate"
        case hrvSdnnMs = "hrv_sdnn_ms"
        case steps
        case bodyFatPct = "body_fat_pct"
        case waistCm = "waist_cm"
        case hipCm = "hip_cm"
    }
}

@MainActor
@Observable
final class TrendsViewModel {
    enum State {
        case loading
        case loaded([MetricGroup])
        case failed(String)
    }

    private(set) var state: State

    /// Szerokość okna. Zmiana przeładowuje dane.
    var window: TrendWindow = .month

    /// Ile okien wstecz od dziś. 0 = bieżące, 1 = poprzednie, itd.
    private(set) var page = 0

    /// Podgląd wstrzykuje gotowy stan i nie ma czego dociągać — bez tej flagi
    /// każdy `#Preview` uderzałby w sieć i kończył na ekranie błędu.
    private let autoLoads: Bool

    init(state: State = .loading) {
        self.state = state
        autoLoads = { if case .loading = state { true } else { false } }()
    }

    /// Granice widocznego okna, obie włącznie.
    ///
    /// `now` jest parametrem, a nie `Date()` w środku: bez tego dwa odczyty
    /// z rzędu dostają czasy różniące się o mikrosekundy, a wtedy odległość
    /// między oknami przestaje być całkowitą liczbą dni.
    func visibleRange(now: Date = Date()) -> (from: Date, to: Date) {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -page * window.days, to: now) ?? now
        let start = calendar.date(byAdding: .day, value: -(window.days - 1), to: end) ?? end
        return (start, end)
    }

    /// To samo okno co `periodLabel`, tylko dla wykresu.
    var visibleSpan: DaySpan {
        let (from, to) = visibleRange()
        return DaySpan(from: Self.isoDate(from), to: Self.isoDate(to))
    }

    var periodLabel: String {
        let (from, to) = visibleRange()
        let polish = Locale.autoupdatingCurrent
        return from.formatted(.dateTime.locale(polish).day().month(.abbreviated))
            + " – "
            + to.formatted(.dateTime.locale(polish).day().month(.abbreviated).year())
    }

    var canGoForward: Bool { page > 0 }

    func shift(by pages: Int) {
        page = max(0, page + pages)
    }

    /// Wołane przy każdym wejściu na zakładkę.
    ///
    /// Ekran wczytywał się dotąd raz na uruchomienie, więc wpis zrobiony
    /// w czacie nie pojawiał się tu aż do pull-to-refresh. `load()` nie cofa
    /// stanu do `.loading`, więc dane zostają na ekranie, dopóki nie przyjdą nowe.
    func refresh() async {
        guard autoLoads else { return }
        await load()
    }

    func load() async {
        do {
            let (fromDate, toDate) = visibleRange()
            let from = Self.isoDate(fromDate)
            let to = Self.isoDate(toDate)
            let db = AppSupabase.client

            async let scores: [ScoreRow] = db.from("score_snapshots")
                .select("score_date, score_total, components")
                .gte("score_date", value: from)
                .lte("score_date", value: to)
                .order("score_date").execute().value
            async let weights: [WeightRow] = db.from("weight_log")
                .select("measured_at, weight_kg")
                .gte("measured_at", value: from)
                .lte("measured_at", value: to)
                .order("measured_at").execute().value
            async let activity: [ActivityRow] = db.from("activity_logs")
                .select("logged_date, activity_minutes")
                .gte("logged_date", value: from)
                .lte("logged_date", value: to)
                .order("logged_date").execute().value
            async let health: [HealthRow] = db.from("health_metrics")
                .select("""
                    metric_date, sleep_asleep_minutes, sleep_deep_minutes, \
                    sleep_regularity_index, exercise_minutes, vo2max, resting_heart_rate, hrv_sdnn_ms, \
                    steps, body_fat_pct, waist_cm, hip_cm
                    """)
                .gte("metric_date", value: from)
                .lte("metric_date", value: to)
                .order("metric_date").execute().value

            state = .loaded(
                try await Self.build(
                    scores: scores, weights: weights,
                    activity: activity, health: health
                )
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Kolejność kafelków idzie za wagami z formuły v3: najpierw score, potem
    /// sen (30%), wydolność (25%), skład ciała (20%), regeneracja (15%),
    /// a na końcu ruch — v3 go nie punktuje, ale opisuje dzień.
    ///
    /// Metryki bez ani jednego punktu są odsiewane — kafelek metryki, której
    /// nigdy nie zmierzono, nie niesie żadnej informacji. Pojawi się sam, gdy
    /// pierwsza wartość wejdzie z zegarka albo z „Pomiarów" w czacie.
    private static func build(
        scores: [ScoreRow],
        weights: [WeightRow],
        activity: [ActivityRow],
        health: [HealthRow]
    ) -> [MetricGroup] {
        let consistencyPoints = scores.compactMap { row -> SeriesPoint? in
            part(row.components, component: "sleep", key: "consistency")
                .map { SeriesPoint(date: row.scoreDate, value: $0) }
        }

        return grouped([
            Metric(id: "score", title: String(localized: "Longevity Score"), unit: "/100", positiveHigher: true, role: .total,
                   points: scores.map { SeriesPoint(date: $0.scoreDate, value: $0.scoreTotal) }),

            // Sen — 33% w v3
            //
            // Jednostka pusta, bo siedzi w samej wartości („8h 40min") — karta
            // nie ma jej dopisywać drugi raz. Godziny bez zaokrąglenia do
            // dziesiątych, bo z 8,6 nie da się już odzyskać 8 h 37 min.
            Metric(id: "sleep_hours", title: String(localized: "Sen"), unit: "", positiveHigher: true, role: .feeds(component: ScoreComponents.label(forComponent: "sleep"), weight: 0.33),
                   format: .duration,
                   points: series(health) { $0.sleepAsleepMinutes.map { Double($0) / 60 } }),
            Metric(id: "sleep_deep", title: String(localized: "Sen głęboki"), unit: "%", positiveHigher: true, role: .feeds(component: ScoreComponents.label(forComponent: "sleep"), weight: 0.33),
                   points: series(health) {
                       deepSleepShare(deep: $0.sleepDeepMinutes, asleep: $0.sleepAsleepMinutes)
                   }),
            Metric(id: "sleep_regularity", title: String(localized: "Regularność pory snu (SRI)"), unit: "", positiveHigher: true,
                   role: .feeds(component: ScoreComponents.label(forComponent: "sleep"), weight: 0.33),
                   points: series(health) { $0.sleepRegularityIndex }),
            Metric(id: "sleep_consistency", title: String(localized: "Równa długość snu"), unit: "/100", positiveHigher: true,
                   role: .feeds(component: ScoreComponents.label(forComponent: "sleep"), weight: 0.33), points: consistencyPoints),

            // Wydolność — 28%
            Metric(id: "vo2max", title: String(localized: "VO₂max"), unit: "ml/kg/min", positiveHigher: true, role: .feeds(component: ScoreComponents.label(forComponent: "vo2max"), weight: 0.28),
                   points: series(health) { $0.vo2max }),

            // Skład ciała — 22%
            Metric(id: "weight", title: String(localized: "Waga"), unit: "kg", positiveHigher: false, role: .feeds(component: ScoreComponents.label(forComponent: "body"), weight: 0.22),
                   points: weights.map { SeriesPoint(date: $0.measuredAt, value: $0.weightKg) }),
            Metric(id: "whr", title: String(localized: "WHR (talia/biodra)"), unit: "", positiveHigher: false, role: .feeds(component: ScoreComponents.label(forComponent: "body"), weight: 0.22),
                   points: series(health) { waistToHipRatio(waist: $0.waistCm, hip: $0.hipCm) }),
            Metric(id: "body_fat", title: String(localized: "Tkanka tłuszczowa"), unit: "%", positiveHigher: false,
                   role: .feeds(component: ScoreComponents.label(forComponent: "body"), weight: 0.22), points: series(health) { $0.bodyFatPct }),

            // Regeneracja — 17%
            Metric(id: "resting_hr", title: String(localized: "Tętno spoczynkowe"), unit: "bpm", positiveHigher: false, role: .feeds(component: ScoreComponents.label(forComponent: "regeneration"), weight: 0.17),
                   points: series(health) { $0.restingHeartRate }),
            Metric(id: "hrv", title: String(localized: "HRV (SDNN)"), unit: "ms", positiveHigher: true, role: .feeds(component: ScoreComponents.label(forComponent: "regeneration"), weight: 0.17),
                   points: series(health) { $0.hrvSdnnMs }),

            // Poza wynikiem — v3 tego nie punktuje, ale opisuje dzień.
            // Z HealthKit `appleExerciseTime`. Ta sama kolumna przyjmie kiedyś
            // minuty intensywności z Garmina — to ten sam pomiar pod inną nazwą
            // handlową, więc nie zakładamy dla niego osobnego miejsca.
            Metric(id: "exercise_minutes", title: String(localized: "Minuty ćwiczeń"), unit: "min", positiveHigher: true,
                   role: .informational, points: series(health) { $0.exerciseMinutes.map(Double.init) }),
            Metric(id: "steps", title: String(localized: "Kroki"), unit: "", positiveHigher: true, role: .informational,
                   points: series(health) { $0.steps.map(Double.init) }),
            Metric(id: "activity", title: String(localized: "Ruch (wpisany)"), unit: "min", positiveHigher: true, role: .informational,
                   points: activity.map { SeriesPoint(date: $0.loggedDate, value: $0.activityMinutes) }),
        ]
        .filter { !$0.points.isEmpty })
    }

    /// Wartość składowej ze snapshotu. Aplikacja niczego nie przelicza —
    /// czyta dokładnie tę liczbę, którą dashboard pokazuje pod score'em.
    private static func part(
        _ components: ScoreComponents?,
        component: String,
        key: String
    ) -> Double? {
        components?.parts?[component]?.first { $0.key == key }?.value
    }

    /// Sekcje w kolejności pierwszego wystąpienia metryki — dzięki temu układ
    /// listy powyżej jest jedynym miejscem, które o tej kolejności decyduje.
    ///
    /// Internal, nie private: kolejność sekcji jest tym, co użytkownik zauważy
    /// jako pierwsze, gdy się rozjedzie z dashboardem.
    static func grouped(_ metrics: [Metric]) -> [MetricGroup] {
        var order: [String] = []
        var byGroup: [String: [Metric]] = [:]

        for metric in metrics {
            let id = metric.role.groupID
            if byGroup[id] == nil { order.append(id) }
            byGroup[id, default: []].append(metric)
        }

        return order.compactMap { id in
            guard let items = byGroup[id], let role = items.first?.role else { return nil }
            return MetricGroup(
                id: id,
                title: role.groupTitle,
                weight: role.groupWeight,
                metrics: items
            )
        }
    }

    /// `health_metrics` ma prawie wszystkie kolumny opcjonalne, więc każdy
    /// szereg powstaje z pominięciem dni bez pomiaru.
    private static func series(
        _ rows: [HealthRow],
        _ value: (HealthRow) -> Double?
    ) -> [SeriesPoint] {
        rows.compactMap { row in
            value(row).map { SeriesPoint(date: row.metricDate, value: $0) }
        }
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    /// Udział snu głębokiego w całości snu. Internal, nie private — razem z WHR
    /// to jedyne miejsca w tym pliku, gdzie coś się liczy, a nie przepisuje.
    ///
    /// Mianownikiem jest czas SNU, nie czas w łóżku — inaczej wynik zależałby od
    /// tego, jak długo ktoś czyta przed zaśnięciem.
    static func deepSleepShare(deep: Int?, asleep: Int?) -> Double? {
        guard let deep, let asleep, asleep > 0 else { return nil }
        return round1(Double(deep) / Double(asleep) * 100)
    }

    /// Waist-to-hip ratio. Biodra mogą przyjść tylko z ręcznego wpisu, więc
    /// najczęstszym wynikiem jest `nil` i to jest poprawne zachowanie.
    static func waistToHipRatio(waist: Double?, hip: Double?) -> Double? {
        guard let waist, let hip, hip > 0 else { return nil }
        return (waist / hip * 100).rounded() / 100
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

}

extension Metric {
    /// Sortowanie po dacie jest w inicjalizatorze, bo szeregi sklejają się
    /// z kilku tabel i nie wszystkie przychodzą uporządkowane.
    init(
        id: String,
        title: String,
        unit: String,
        positiveHigher: Bool,
        role: MetricRole,
        format: MetricFormat = .decimal,
        points: [SeriesPoint]
    ) {
        self.id = id
        self.title = title
        self.unit = unit
        self.positiveHigher = positiveHigher
        self.role = role
        self.format = format
        self.points = points.sorted { $0.date < $1.date }
    }
}
