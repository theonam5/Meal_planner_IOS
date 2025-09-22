import Foundation

/// Index "pauvre" mais moins idiot: propose K candidats pertinents pour chaque item extrait.
/// Combine des heuristiques simples (exact/prefixe/contient + ratio) pour conserver au moins 5 candidats triés par pertinence.
struct CatalogIndex {
    struct Candidate {
        let id: Int
        let name: String
        let canonicalName: String?
        let score: Double
    }

    private struct Entry {
        let ingredient: Ingredient
        let displayName: String
        let normalizedOptions: [String]
    }

    private struct Metrics {
        let score: Double
        static let zero = Metrics(score: 0)
    }

    static func buildCandidates(
        for items: [LLM.Item],
        queryNames: [String]? = nil,
        from catalog: [Int: Ingredient],
        k: Int = 6
    ) -> [Int: [Candidate]] {
        let limit = max(k, 5)
        let entries: [Entry] = catalog.values.map { ingredient in
            let displayName = preferredName(for: ingredient)
            var normalized = Set<String>()
            normalized.insert(normalizeForMatch(ingredient.name))
            if let canonical = ingredient.canonicalName?.trimmingCharacters(in: .whitespacesAndNewlines), !canonical.isEmpty {
                normalized.insert(normalizeForMatch(canonical))
            }
            let options = normalized.filter { !$0.isEmpty }
            return Entry(ingredient: ingredient, displayName: displayName, normalizedOptions: Array(options))
        }

        #if DEBUG
        print("[CatalogIndex] catalogue=\(entries.count) refs")
        #endif

        var result: [Int: [Candidate]] = [:]

        for (idx, item) in items.enumerated() {
            let rawQuery = (queryNames?[idx] ?? item.n).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedQuery = normalizeForMatch(rawQuery)

            let ranked: [Candidate]
            if normalizedQuery.isEmpty {
                ranked = entries
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                    .prefix(limit)
                    .map { entry in
                        Candidate(
                            id: entry.ingredient.id,
                            name: entry.ingredient.name,
                            canonicalName: entry.ingredient.canonicalName,
                            score: 0
                        )
                    }
            } else {
                ranked = entries
                    .map { entry -> Candidate in
                        let metrics = bestMetrics(for: normalizedQuery, options: entry.normalizedOptions)
                        return Candidate(
                            id: entry.ingredient.id,
                            name: entry.ingredient.name,
                            canonicalName: entry.ingredient.canonicalName,
                            score: metrics.score
                        )
                    }
                    .sorted { lhs, rhs in
                        if abs(lhs.score - rhs.score) < 0.0001 {
                            return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
                        }
                        return lhs.score > rhs.score
                    }
                    .prefix(limit)
                    .map { $0 }
            }

            result[idx] = ranked

            #if DEBUG
            let preview = ranked.prefix(5).map { candidate -> String in
                let label = displayName(for: candidate)
                return "\(label)(id:\(candidate.id),score:\(String(format: "%.3f", candidate.score)))"
            }.joined(separator: ", ")
            print("[CatalogIndex] query='\(rawQuery)' → \(preview)")
            #endif
        }

        return result
    }

    // MARK: - Scoring helpers

    private static func bestMetrics(for query: String, options: [String]) -> Metrics {
        guard !options.isEmpty else { return .zero }
        var best = Metrics.zero
        for option in options where !option.isEmpty {
            let metrics = metrics(for: query, candidate: option)
            if metrics.score > best.score {
                best = metrics
            }
        }
        return best
    }

    private static func metrics(for query: String, candidate: String) -> Metrics {
        guard !query.isEmpty, !candidate.isEmpty else { return .zero }
        let exact = query == candidate
        let prefix = candidate.hasPrefix(query) || query.hasPrefix(candidate)
        let contains = candidate.contains(query) || query.contains(candidate)
        let ratio = simpleRatio(query, candidate)
        let jacc = jaccardTokens(query, candidate)
        let tri = trigramSim(query, candidate)
        let fuzzy = max(ratio, max(jacc, tri))
        let score = (exact ? 400.0 : 0.0) + (prefix ? 40.0 : 0.0) + (contains ? 20.0 : 0.0) + fuzzy
        return Metrics(score: score)
    }

    private static func preferredName(for ingredient: Ingredient) -> String {
        if let canonical = ingredient.canonicalName?.trimmingCharacters(in: .whitespacesAndNewlines), !canonical.isEmpty {
            return canonical
        }
        return ingredient.name
    }

    private static func displayName(for candidate: Candidate) -> String {
        if let canonical = candidate.canonicalName?.trimmingCharacters(in: .whitespacesAndNewlines), !canonical.isEmpty {
            return canonical
        }
        return candidate.name
    }

    // MARK: - Normalisation agressive pour le matching (pas pour l’affichage)

    private static func normalizeForMatch(_ s: String) -> String {
        var x = s
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "Œ", with: "oe")
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

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

        x = x.replacingOccurrences(of: "[^a-z0-9\\s-]", with: " ", options: .regularExpression)
        x = x.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)

        let toks = x.split(separator: " ").map { reduceFrench(String($0)) }
        return toks.joined(separator: " ")
    }

    private static func reduceFrench(_ t: String) -> String {
        var s = t
        s = s.replacingOccurrences(of: #"hach(e|ee|es|er|ez)$"#, with: "hach", options: .regularExpression)
        if s.count > 3 {
            s = s.replacingOccurrences(of: "(ees|ees|es|e|s|x)$", with: "", options: .regularExpression)
        }
        return s
    }

    // MARK: - Similarité auxiliaire

    private static func jaccardTokens(_ a: String, _ b: String) -> Double {
        let A = Set(a.split(separator: " ").map(String.init))
        let B = Set(b.split(separator: " ").map(String.init))
        if A.isEmpty || B.isEmpty { return 0 }
        let inter = Double(A.intersection(B).count)
        let uni   = Double(A.union(B).count)
        return inter / uni
    }

    private static func trigramSim(_ a: String, _ b: String) -> Double {
        let A = trigrams(a); let B = trigrams(b)
        if A.isEmpty || B.isEmpty { return 0 }
        let inter = Double(A.intersection(B).count)
        let denom = sqrt(Double(A.count) * Double(B.count))
        return denom == 0 ? 0 : inter / denom
    }

    private static func trigrams(_ s: String) -> Set<String> {
        let str = "  " + s + "  "
        if str.count < 3 { return [] }
        var set = Set<String>()
        let arr = Array(str)
        for i in 0..<(arr.count - 2) {
            set.insert(String(arr[i...i+2]))
        }
        return set
    }

    private static func simpleRatio(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let distance = Double(levenshteinDistance(a, b))
        let maxLen = Double(max(a.count, b.count))
        guard maxLen > 0 else { return 0 }
        return max(0, 1 - distance / maxLen)
    }

    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        let aChars = Array(a)
        let bChars = Array(b)
        var previous = Array(0...bChars.count)

        for (i, aChar) in aChars.enumerated() {
            var current = [i + 1]
            for (j, bChar) in bChars.enumerated() {
                let cost = (aChar == bChar) ? 0 : 1
                let deletion = previous[j + 1] + 1
                let insertion = current[j] + 1
                let substitution = previous[j] + cost
                current.append(min(deletion, insertion, substitution))
            }
            previous = current
        }
        return previous.last ?? max(a.count, b.count)
    }
}
