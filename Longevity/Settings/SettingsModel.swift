import Foundation
import Observation
import Supabase

/// Słowniki 1:1 z `app/settings/page.tsx`.
enum SettingsOptions {
    static let goals = [
        ("energy", "Więcej energii"),
        ("sleep", "Lepszy sen"),
        ("stress", "Mniej stresu"),
        ("performance", "Lepsza forma sportowa"),
        ("longevity", "Długowieczność"),
    ]
    static let sexes = [
        ("male", "Mężczyzna"),
        ("female", "Kobieta"),
        ("other", "Inna"),
        ("prefer_not_to_say", "Wolę nie podawać"),
    ]
    static let bodyTypes = [
        ("athletic", "Wysportowana"),
        ("standard", "Standardowa"),
        ("overweight", "Nadwaga"),
        ("obese", "Otyłość"),
    ]
    /// Indeks = wartość `weekly_recap_dow` (0 = niedziela).
    static let weekdays = [
        "Niedziela", "Poniedziałek", "Wtorek", "Środa",
        "Czwartek", "Piątek", "Sobota",
    ]
}

private struct ProfileRow: Decodable {
    let fullName: String?
    let telegramChatId: Int?
    let birthDate: String?
    let sex: String?
    let heightCm: Double?
    let weightKg: Double?
    let primaryGoal: String?
    let bodyType: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case telegramChatId = "telegram_chat_id"
        case birthDate = "birth_date"
        case sex
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case primaryGoal = "primary_goal"
        case bodyType = "body_type"
    }
}

private struct PrefsRow: Decodable {
    let nudgesEnabled: Bool
    let nudgeTimeLocal: String
    let weeklyRecapEnabled: Bool
    let weeklyRecapDow: Int

    enum CodingKeys: String, CodingKey {
        case nudgesEnabled = "nudges_enabled"
        case nudgeTimeLocal = "nudge_time_local"
        case weeklyRecapEnabled = "weekly_recap_enabled"
        case weeklyRecapDow = "weekly_recap_dow"
    }
}

private struct ProfilePayload: Encodable {
    let full_name: String
    let birth_date: String?
    let sex: String?
    let height_cm: Double?
    let weight_kg: Double?
    let primary_goal: String?
    let body_type: String?
}

private struct PrefsPayload: Encodable {
    let user_id: String
    let nudges_enabled: Bool
    let nudge_time_local: String
    let weekly_recap_enabled: Bool
    let weekly_recap_dow: Int
    let timezone: String
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
    var weightKg = ""
    var primaryGoal = ""
    var bodyType = ""

    // Integracje
    var telegramLinked = false

    // Powiadomienia
    var nudgesEnabled = true
    var nudgeTime = Date()
    var weeklyRecapEnabled = true
    var weeklyRecapDow = 0

    // Hasła nie zmienia się w formularzu ustawień — wysyłamy link na maila.
    var passwordStatus: String?
    var passwordIsError = false
    var isSendingReset = false

    /// Jedna wartość reprezentująca cały formularz — `onChange` na niej
    /// wystarczy zamiast modyfikatora przy każdym polu.
    var profileSignature: String {
        [
            fullName, String(birthDateIsSet), String(birthDate.timeIntervalSince1970),
            sex, heightCm, weightKg, primaryGoal, bodyType,
        ].joined(separator: "|")
    }

    var prefsSignature: String {
        [
            String(nudgesEnabled), String(nudgeTime.timeIntervalSince1970),
            String(weeklyRecapEnabled), String(weeklyRecapDow),
        ].joined(separator: "|")
    }

    private var savedProfileSignature: String?
    private var savedPrefsSignature: String?
    private var profileSaveTask: Task<Void, Never>?
    private var prefsSaveTask: Task<Void, Never>?
    private var statusResetTask: Task<Void, Never>?

    // MARK: - Wczytanie

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await AppSupabase.client.auth.session
            let userId = session.user.id.uuidString
            email = session.user.email ?? ""

            let profile: ProfileRow = try await AppSupabase.client
                .from("profiles")
                .select("full_name, telegram_chat_id, birth_date, sex, height_cm, weight_kg, primary_goal, body_type")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            fullName = profile.fullName ?? ""
            telegramLinked = profile.telegramChatId != nil
            sex = profile.sex ?? ""
            heightCm = profile.heightCm.map { Self.trimZero($0) } ?? ""
            weightKg = profile.weightKg.map { Self.trimZero($0) } ?? ""
            primaryGoal = profile.primaryGoal ?? ""
            bodyType = profile.bodyType ?? ""
            if let iso = profile.birthDate, let parsed = Self.dateParser.date(from: iso) {
                birthDate = parsed
                birthDateIsSet = true
            }

            // Web robi tu upsert, żeby wiersz preferencji na pewno istniał.
            let prefs: PrefsRow = try await AppSupabase.client
                .from("notification_prefs")
                .upsert(["user_id": userId], onConflict: "user_id")
                .select("nudges_enabled, nudge_time_local, weekly_recap_enabled, weekly_recap_dow")
                .single()
                .execute()
                .value

            nudgesEnabled = prefs.nudgesEnabled
            weeklyRecapEnabled = prefs.weeklyRecapEnabled
            weeklyRecapDow = prefs.weeklyRecapDow
            nudgeTime = Self.timeParser.date(from: String(prefs.nudgeTimeLocal.prefix(5)))
                ?? Self.timeParser.date(from: "20:00")!

            // Punkt odniesienia dla auto-zapisu: dopóki sygnatura się nie ruszy,
            // nic nie wysyłamy. Bez tego samo wypełnienie pól zapisywałoby z powrotem.
            savedProfileSignature = profileSignature
            savedPrefsSignature = prefsSignature
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

    func prefsChanged() {
        guard savedPrefsSignature != nil, prefsSignature != savedPrefsSignature else { return }
        prefsSaveTask?.cancel()
        prefsSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.savePreferences()
        }
    }

    /// Domyka zapis natychmiast, gdy widok znika — inaczej ostatnia zmiana
    /// mogłaby zginąć razem z odliczaniem debounce'u.
    func flushPendingSaves() async {
        profileSaveTask?.cancel()
        prefsSaveTask?.cancel()
        if profileSignature != savedProfileSignature { await saveProfile() }
        if prefsSignature != savedPrefsSignature { await savePreferences() }
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
                weight_kg: Double(weightKg.replacingOccurrences(of: ",", with: ".")),
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

    private func savePreferences() async {
        let signature = prefsSignature
        saveState = .saving

        do {
            let userId = try await AppSupabase.client.auth.session.user.id.uuidString
            let payload = PrefsPayload(
                user_id: userId,
                nudges_enabled: nudgesEnabled,
                nudge_time_local: "\(Self.timeParser.string(from: nudgeTime)):00",
                weekly_recap_enabled: weeklyRecapEnabled,
                weekly_recap_dow: weeklyRecapDow,
                timezone: "Europe/Warsaw"
            )
            try await AppSupabase.client
                .from("notification_prefs")
                .upsert(payload, onConflict: "user_id")
                .execute()

            savedPrefsSignature = signature
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
            passwordStatus = "Wysłaliśmy link na \(email)"
        } catch {
            passwordIsError = true
            passwordStatus = error.localizedDescription
        }
    }

    func signOut() async {
        await flushPendingSaves()
        try? await AppSupabase.client.auth.signOut()
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
