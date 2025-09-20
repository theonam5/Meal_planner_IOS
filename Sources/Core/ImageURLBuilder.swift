import Foundation

enum ImageURLBuilder {
    // Base fixe demandée
    private static let base = URL(string: "https://cwlyrciwsvectxjsrxot.supabase.co/storage/v1/object/public/recettes/")!

    /// Construit l'URL d'image à partir de la colonne `photo_recette`
    /// Accepte: URL http(s), "storage/v1/object/public/recettes/...", "recettes/...", ou juste "fichier.jpg"
    static func recetteURL(from photoPath: String?) -> URL? {
        guard var raw = photoPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        // Déjà une URL absolue ? On la rend telle quelle.
        if let u = URL(string: raw), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return u
        }

        // Nettoyage des préfixes pour éviter les doublons "recettes/recettes/..."
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if raw.hasPrefix("storage/v1/object/public/") {
            raw.removeFirst("storage/v1/object/public/".count)
        }
        if raw.hasPrefix("recettes/") {
            raw.removeFirst("recettes/".count)
        }

        // Encodage propre (espaces, accents)
        let encoded = raw
            .split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")

        // Concaténation fiable
        return URL(string: encoded, relativeTo: base)
    }
}
