import Foundation
import Supabase

enum AppSupabase {
    static let client = SupabaseClient(
        supabaseURL: URL(string: AppSecrets.supabaseURL)!,
        supabaseKey: AppSecrets.supabaseAnonKey,
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                storage: AuthClient.Configuration.defaultLocalStorage,
                // Bez tego SDK emituje `.initialSession` DOPIERO po próbie
                // odświeżenia tokenu w sieci — a gdy ta próba się nie uda
                // (offline, chwilowy błąd Supabase, zużyty refresh token),
                // emituje `nil` i `RootView` wyrzuca użytkownika na ekran
                // logowania mimo poprawnej sesji w Keychainie.
                //
                // `true` emituje sesję zapisaną lokalnie od razu, niezależnie
                // od jej ważności; odświeżenie leci w tle, a prawdziwe
                // wylogowanie przychodzi osobnym zdarzeniem `.signedOut`.
                // Autor SDK zaleca tę wartość i robi z niej domyślną
                // w kolejnym major release (supabase-swift#822).
                emitLocalSessionAsInitialSession: true
            )
        )
    )

    /// Adres wersji web. Link resetujący hasło musi trafić na stronę, która
    /// obsłuży token recovery — w repo webowym robi to `/update-password`.
    /// Musi być na liście Redirect URLs w ustawieniach Auth w Supabase.
    static let webBaseURL = URL(string: "https://longevity-chi.vercel.app")!
}
