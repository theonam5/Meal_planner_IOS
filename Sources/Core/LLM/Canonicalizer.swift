import Foundation

enum Canonicalizer {
    static func canonicalize(
        rows: [DetectedRow],
        catalog: [Int: Ingredient],
        using client: any LLM.Client,
        confidenceThreshold: Double = 0.8
    ) async throws -> [DetectedRow] {
        // 1) Construire items LLM
        let items: [LLM.Item] = rows.map { .init(n: $0.name, q: $0.quantity, u: $0.unit) }

        // 2) Candidats locaux
        let cand = CatalogIndex.buildCandidates(for: items, from: catalog)
        let payload = try makePayload(items: items, candidates: cand)

        // 3) Appel LLM
        let res = try await client.canonicalize(payloadJSON: payload)

        // 4) Appliquer mapping
        var out = rows
        for m in res.mapped {
            guard m.idx >= 0, m.idx < out.count else { continue }
            guard let cid = m.canonical_id, let cname = m.canonical_name, m.confidence >= confidenceThreshold else {
                continue // on laisse le nom d’origine si inconnu ou faible confiance
            }
            // Remplace le nom par le canon (tu peux aussi stocker cid dans un champ si tu veux)
            out[m.idx].name = cname
        }
        return out
    }

    private static func makePayload(
        items: [LLM.Item],
        candidates: [Int: [CatalogIndex.Candidate]]
    ) throws -> String {
        let canonCandidates: [String: [LLM.CanonCandidate]] = Dictionary(
            uniqueKeysWithValues: candidates.map { (idx, arr) in
                let v = arr.map { LLM.CanonCandidate(id: $0.id, name: $0.name) }
                return (String(idx), v)
            }
        )
        let req = LLM.CanonRequest(items: items, candidates: canonCandidates)
        let data = try JSONEncoder().encode(req)
        return String(data: data, encoding: .utf8) ?? #"{"items":[],"candidates":{}}"#
    }
}
