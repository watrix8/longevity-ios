import Foundation
import Supabase

enum AppSupabase {
    static let client = SupabaseClient(
        supabaseURL: URL(string: supabaseURL)!,
        supabaseKey: supabaseAnonKey
    )

    private static var supabaseURL: String {
        // TODO: Load from environment/config
        "https://your-project.supabase.co"
    }

    private static var supabaseAnonKey: String {
        // TODO: Load from environment/config
        "your-anon-key"
    }
}
