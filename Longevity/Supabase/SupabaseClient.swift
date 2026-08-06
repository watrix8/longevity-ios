import Foundation
import Supabase

enum AppSupabase {
    static let client = SupabaseClient(
        supabaseURL: URL(string: AppSecrets.supabaseURL)!,
        supabaseKey: AppSecrets.supabaseAnonKey
    )
}
