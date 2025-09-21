import Foundation

/// Index "pauvre" mais moins idiot: propose K candidats pertinents pour chaque item extrait.
/// Combine Jaccard(token), trigrammes(caractères) et bonus sous-chaîne/prefixe.
struct CatalogIndex {
    struct Candidate { let id: Int; let name: String }

    static func buildCandidates(
        for items: [LLM.Item],
        queryNames: [String]? = nil,                  // optionnel: noms "nettoyés" passés par le canonicalizer
        from catalog: [Int: Ingredient],
        k: Int = 6
    ) -> [Int: [Candidate]] {

        // Prépare l’index: on travaille sur Ingredient.name (ton "canon")
        let entries: [(id: Int, raw: String, norm: String)] = catalog.values.map { ing in
            let raw = ing.name
            return (id: ing.id, raw: raw, norm: normalizeForMatch(raw))
        }

        #if DEBUG
        print("[CatalogIndex] catalogue=\(entries.count) refs")
        #endif

        var result: [Int: [Candidate]] = [:]

        for (idx, it) in items.enumerated() {
            let queryRaw = (queryNames?[idx] ?? it.n)
            let q = normalizeForMatch(queryRaw)

            // Score combiné
            let ranked = entries
                .map { e -> (Int, String, Double) in
                    let s = combinedScore(query: q, candidate: e.norm)
                    return (e.id, e.raw, s)
                }
                .sorted { $0.2 > $1.2 }
                .prefix(k)
                .map { Candidate(id: $0.0, name: $0.1) }

            result[idx] = Array(ranked)

            #if DEBUG
            let preview = ranked.prefix(5).map { "\($0.name)(id:\($0.id))" }.joined(separator: ", ")
            print("[CatalogIndex] query='\(queryRaw)' → \(preview)")
            #endif
        }

        return result
    }

    // MARK: - Normalisation agressive pour le matching (pas pour l’affichage)
    private static func normalizeForMatch(_ s: String) -> String {
        var x = s
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "Œ", with: "oe")
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        // retire tailles/mentions parasites: "(400 g)", "(facultatif)"
        x = x.replacingOccurrences(
            of: #"(?i)\s*\((?:~?\d+(?:[.,]\d+)?\s*(?:mg|g|kg|ml|cl|l))\)\s*"#,
            with: " ",
            options: .regularExpression
        )
        x = x.replacingOccurrences(
            of: #"(?i)\s*\((?:facultatif|optionnel)\)\s*"#,
            with: " ",
            options: .regularExpression
        )

        // garde que lettres/chiffres/espaces/tirets
        x = x.replacingOccurrences(of: "[^a-z0-9\\s-]", with: " ", options: .regularExpression)
        x = x.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)

        // stemming fr ultra-simple: haché/hachée/haches → hach ; pluriels/féminins "e/es/x/s"
        let toks = x.split(separator: " ").map { reduceFrench(String($0)) }
        return toks.joined(separator: " ")
    }

    private static func reduceFrench(_ t: String) -> String {
        var s = t
        // normalise "hachee/hashee/hache" vers "hach"
        s = s.replacingOccurrences(of: #"hach(e|ee|es|er|ez)$"#, with: "hach", options: .regularExpression)
        // pluriels/féminins grossiers
        if s.count > 3 {
            s = s.replacingOccurrences(of: "(ees|ees|es|e|s|x)$", with: "", options: .regularExpression)
        }
        return s
    }

    // MARK: - Scoring combiné
    private static func combinedScore(query q: String, candidate c: String) -> Double {
        if q == c { return 1.0 }

        let jTok = jaccardTokens(q, c)                         // 0..1
        let tri  = trigramSim(q, c)                            // 0..1

        var s = 0.7 * jTok + 0.3 * tri

        // bonus si sous-chaîne/prefixe après normalisation
        if c.contains(q) || q.contains(c) { s += 0.15 }
        if c.hasPrefix(q) || q.hasPrefix(c) { s += 0.10 }

        // petit bonus thématique: présence du radical "hach" des deux côtés
        if q.contains("hach"), c.contains("hach") { s += 0.08 }

        return min(1.0, s)
    }

    // Jaccard de tokens
    private static func jaccardTokens(_ a: String, _ b: String) -> Double {
        let A = Set(a.split(separator: " ").map(String.init))
        let B = Set(b.split(separator: " ").map(String.init))
        if A.isEmpty || B.isEmpty { return 0 }
        let inter = Double(A.intersection(B).count)
        let uni   = Double(A.union(B).count)
        return inter / uni
    }

    // Similarité trigrammes de caractères (cosinus-like ultra simple)
    private static func trigramSim(_ a: String, _ b: String) -> Double {
        let A = trigrams(a); let B = trigrams(b)
        if A.isEmpty || B.isEmpty { return 0 }
        let inter = Double(A.intersection(B).count)
        let denom = sqrt(Double(A.count) * Double(B.count))
        return denom == 0 ? 0 : inter / denom
    }

    private static func trigrams(_ s: String) -> Set<String> {
        let str = "  " + s + "  "   // padding
        if str.count < 3 { return [] }
        var set = Set<String>()
        let arr = Array(str)
        for i in 0..<(arr.count - 2) {
            set.insert(String(arr[i...i+2]))
        }
        return set
    }
}
