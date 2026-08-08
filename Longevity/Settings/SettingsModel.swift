import Foundation
import Observation
import Supabase

/// Słowniki 1:1 z `app/settings/page.tsx`.
enum SettingsOptions {
    /// Klucze lecą do bazy i są stałe; etykiety idą przez String Catalog.
    static var goals: [(String, String)] {
        [
            ("energy", String(localized: "Więcej energii")),
            ("sleep", String(localized: "Lepszy sen")),
            ("stress", String(localized: "Mniej stresu")),
            ("performance", String(localized: "Lepsza forma sportowa")),
            ("longevity", String(localized: "Długowieczność")),
        ]
    }
    static var sexes: [(String, String)] {
        [
            ("male", String(localized: "Mężczyzna")),
            ("female", String(localized: "Kobieta")),
            ("other", String(localized: "Inna")),
            ("prefer_not_to_say", String(localized: "Wolę nie podawać")),
        ]
    }
    static var bodyTypes: [(String, String)] {
        [
            ("athletic", String(localized: "Wysportowana")),
            ("standard", String(localized: "Standardowa")),
            ("overweight", String(localized: "Nadwaga")),
            ("obese", String(localized: "Otyłość")),
        ]
    }
}

private struct ProfileRow: Decodable {
    let fullName: String?
    let birthDate: String?
    let sex: String?
    let heightCm: Double?
    let primaryGoal: String?
    let bodyType: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case birthDate = "birth_date"
        case sex
        case heightCm = "height_cm"
        case primaryGoal = "primary_goal"
        case bodyType = "body_type"
    }
}

private struct ProfilePayload: Encodable {
    let full_name: String
    let birth_date: String?
    let sex: String?
    let height_cm: Double?
    let primary_goal: String?
    let body_type: String?
}

@MainActor
@Observable
final class SettingsViewModel {
    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    var isLoading = true
    var loadError: String?
    private(set) var saveState: SaveState = .idle

    // Zdrowie i dane
    var fullName = ""
    var email = ""
    /// Wartość startowa jest neutralna, a nie „dziś" — data urodzenia równa
    /// dzisiejszej czytałaby się jak realna wartość, gdy jej po prostu nie ma.
    var birthDate = SettingsViewModel.fallbackBirthDate
    /// Nie jest przełącznikiem w UI. Pilnuje, żeby profilowi bez daty urodzenia
    /// nie zapisać placeholdera przy edycji innego pola.
    private(set) var birthDateIsSet = false
    var sex = ""
    var heightCm = ""
    var primaryGoal = ""
    var bodyType = ""

    /// Konto założone przez Apple nie ma tożsamości hasłowej, więc nie ma też
    /// czego resetować — link nigdy by nie przyszedł.
    private(set) var hasPassword = true

    // Hasła nie zmienia się w formularzu ustawień — wysyłamy link na maila.
    var passwordStatus: String?
    var passwordIsError = false
    var isSendingReset = false

    /// Jedna wartość reprezentująca cały formularz — `onChange` na niej
    /// wystarczy zamiast modyfikatora przy każdym polu.
    var profileSignature: String {
        [
            fullName, String(birthDateIsSet), String(birthDate.timeIntervalSince1970),
            sex, heightCm, primaryGoal, bodyType,
        ].joined(separator: "|")
    }

    private var savedProfileSignature: String?
    private var profileSaveTask: Task<Void, Never>?
    private var statusResetTask: Task<Void, Never>?

    // MARK: - Wczytanie

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await AppSupabase.client.auth.session
            let userId = session.user.id.uuidString
            email = session.user.email ?? ""
            hasPassword = Self.hasPasswordIdentity(
                providers: session.user.identities?.map(\.provider) ?? []
            )

            let profile: ProfileRow = try await AppSupabase.client
                .from("profiles")
                .select("full_name, birth_date, sex, height_cm, primary_goal, body_type")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            fullName = profile.fullName ?? ""
            sex = profile.sex ?? ""
            heightCm = profile.heightCm.map { Self.trimZero($0) } ?? ""
            primaryGoal = profile.primaryGoal ?? ""
            bodyType = profile.bodyType ?? ""
            if let iso = profile.birthDate, let parsed = Self.dateParser.date(from: iso) {
                birthDate = parsed
                birthDateIsSet = true
            }

            // Punkt odniesienia dla auto-zapisu: dopóki sygnatura się nie ruszy,
            // nic nie wysyłamy. Bez tego samo wypełnienie pól zapisywałoby z powrotem.
            savedProfileSignature = profileSignature
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Auto-zapis

    func profileChanged() {
        guard savedProfileSignature != nil, profileSignature != savedProfileSignature else { return }
        profileSaveTask?.cancel()
        profileSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.saveProfile()
        }
    }

    /// Domyka zapis natychmiast, gdy widok znika — inaczej ostatnia zmiana
    /// mogłaby zginąć razem z odliczaniem debounce'u.
    func flushPendingSaves() async {
        profileSaveTask?.cancel()
        if profileSignature != savedProfileSignature { await saveProfile() }
    }

    private func saveProfile() async {
        let signature = profileSignature
        saveState = .saving

        do {
            let userId = try await AppSupabase.client.auth.session.user.id.uuidString
            let payload = ProfilePayload(
                full_name: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                birth_date: birthDateIsSet ? Self.dateParser.string(from: birthDate) : nil,
                sex: sex.isEmpty ? nil : sex,
                height_cm: Double(heightCm.replacingOccurrences(of: ",", with: ".")),
                primary_goal: primaryGoal.isEmpty ? nil : primaryGoal,
                body_type: bodyType.isEmpty ? nil : bodyType
            )
            try await AppSupabase.client
                .from("profiles")
                .update(payload)
                .eq("id", value: userId)
                .execute()

            savedProfileSignature = signature
            flash(.saved)
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    private func flash(_ state: SaveState) {
        saveState = state
        statusResetTask?.cancel()
        statusResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if self?.saveState == state { self?.saveState = .idle }
        }
    }

    // MARK: - Akcje jawne

    /// Ten sam przepływ co `app/reset-password/page.tsx` w repo webowym:
    /// mail z linkiem prowadzącym na `/update-password`.
    func sendPasswordReset() async {
        isSendingReset = true
        passwordStatus = nil
        defer { isSendingReset = false }

        do {
            try await AppSupabase.client.auth.resetPasswordForEmail(
                email,
                redirectTo: AppSupabase.webBaseURL.appending(path: "update-password")
            )
            passwordIsError = false
            passwordStatus = String(localized: "Wysłaliśmy link na \(email)")
        } catch {
            passwordIsError = true
            passwordStatus = error.localizedDescription
        }
    }

    func signOut() async {
        await flushPendingSaves()
        HealthSyncModel.shared.reset()
        ChatHistoryCache.clear()
        try? await AppSupabase.client.auth.signOut()
    }

    /// Pusta lista znaczy „nie wiem", nie „brak hasła" — starsze sesje potrafią
    /// nie nieść tożsamości, a ukrycie resetu komuś, kto loguje się mailem,
    /// odcięłoby jedyną drogę do zmiany hasła. W wątpliwości pokazujemy.
    nonisolated static func hasPasswordIdentity(providers: [String]) -> Bool {
        providers.isEmpty || providers.contains("email")
    }

    /// Ustawienie daty z UI oznacza ją jako realnie podaną.
    func setBirthDate(_ date: Date) {
        birthDate = date
        birthDateIsSet = true
    }

    static let fallbackBirthDate: Date = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: "1990-01-01") ?? Date()
    }()

    private static func trimZero(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}
