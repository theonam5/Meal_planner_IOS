import Foundation

public enum LLM {
    public struct Item: Codable {
        public let n: String
        public let q: Double?
        public let u: String?
    }

    public struct Response: Codable {
        public let r: String?      // titre recette
        public let s: Int?         // servings
        public let i: [Item]       // ingrédients
        public let p: [String]?    // étapes (optionnel)
    }

    // ---------- Canonicalisation ----------
    public struct CanonCandidate: Codable {
        public let id: Int
        public let name: String
        public let canonicalName: String?
    }

    public struct CanonRequest: Codable {
        public let items: [Item]
        public let candidates: [String: [CanonCandidate]]  // clé = index en String
    }

    public struct CanonMapped: Codable {
        public let idx: Int
        public let canonical_id: Int?      // null = inconnu
        public let canonical_name: String?
        public let confidence: Double      // 0..1
    }

    public struct CanonResponse: Codable {
        public let mapped: [CanonMapped]
    }

    public protocol Client {
        func parseIngredients(payloadJSON: String) async throws -> Response
        func canonicalize(payloadJSON: String) async throws -> CanonResponse
    }
}

// Fournit une implémentation par défaut (au cas où un client ne l’implémente pas)
public extension LLM.Client {
    func canonicalize(payloadJSON: String) async throws -> LLM.CanonResponse {
        throw NSError(domain: "LLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "canonicalize non implémenté"])
    }
}
