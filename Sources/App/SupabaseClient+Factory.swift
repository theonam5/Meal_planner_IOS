import Foundation
import Supabase

// MARK: - Fabrique du client Supabase
// Récupère SUPABASE_URL et SUPABASE_ANON_KEY depuis Info.plist (ou via xcconfig).
// Si non configuré, on stoppe net (fatalError) pour que tu corriges la config.

enum SB {
    static let shared: SupabaseClient = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let anon = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            let url = URL(string: urlString),
            !anon.isEmpty
        else {
            fatalError("Configure SUPABASE_URL et SUPABASE_ANON_KEY dans Info.plist / .xcconfig")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: anon)
    }()
}
