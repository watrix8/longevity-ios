import Foundation
import Supabase

enum AppSupabase {
    static let client = SupabaseClient(
        supabaseURL: URL(string: AppSecrets.supabaseURL)!,
        supabaseKey: AppSecrets.supabaseAnonKey
    )

    /// Adres wersji web. Link resetujący hasło musi trafić na stronę, która
    /// obsłuży token recovery — w repo webowym robi to `/update-password`.
    /// Musi być na liście Redirect URLs w ustawieniach Auth w Supabase.
    static let webBaseURL = URL(string: "https://longevity-chi.vercel.app")!
}
