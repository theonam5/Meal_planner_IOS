import Foundation

/// Payload minimal pour le LLM (clés courtes = moins de tokens)
struct LI: Codable {
    let s: Int?      // servings (hint)
    let l: [String]  // lines (ingredient candidates)
}

enum MinimalPrep {

    /// Point d'entrée: texte OCR -> Data JSON compact (LI)
    static func preparePayload(from ocrText: String) -> Data? {
        let lines = candidateLines(from: ocrText)
        let servings = detectServings(in: ocrText)
        let payload = LI(s: servings, l: lines)
        let enc = JSONEncoder()          // par défaut: compact, pas d'espaces
        enc.outputFormatting = []        // pas d'options verbeuses
        return try? enc.encode(payload)
    }

    /// Variante pratique si tu veux la chaîne JSON directement
    static func prepareJSONString(from ocrText: String) -> String {
        guard let data = preparePayload(from: ocrText) else { return #"{"s":null,"l":[]}"# }
        return String(data: data, encoding: .utf8) ?? #"{"s":null,"l":[]}"#
    }

    // MARK: - Core minimal

    /// 1) Split + nettoyage léger + fusion des lignes éclatées
    /// 2) Filtrage "ingrédient probable"
    /// 3) Déduplication et taille minimale
    static func candidateLines(from text: String) -> [String] {
        let rawLines = text
            .components(separatedBy: .newlines)
            .map { preclean($0) }
            .filter { !$0.isEmpty }

        let merged = mergeWrappedLines(rawLines)

        // Heuristique très simple: on vire les étapes/meta,
        // on retient ce qui ressemble à un item d'ingrédient.
        var out: [String] = []
        out.reserveCapacity(merged.count)

        for line in merged {
            let l = line.lowercased()

            // Bruit évident
            if l.count < 3 { continue }

            // Écarter instructions/meta les plus courantes
            if isInstruction(l) || isMeta(l) { continue }

            // Ingrédient probable si:
            // - commence par un nombre OU contient une unité connue
            // - ou une puce standard
            if startsWithNumber(l) || containsKnownUnit(l) || startsWithBullet(l) {
                out.append(line)
                continue
            }

            // Sinon, garder si c'est une ligne courte avec au moins un mot "aliment"
            if wordish(l) { out.append(line) }
        }

        // Déduplication basique en insensible casse/espaces
        var seen = Set<String>()
        let dedup = out.compactMap { line -> String? in
            let key = line.folding(options: .diacriticInsensitive, locale: .current)
                          .lowercased()
                          .replacingOccurrences(of: " ", with: "")
            if seen.contains(key) { return nil }
            seen.insert(key)
            return line
        }

        return dedup
    }

    // MARK: - Servings minimaliste

    static func detectServings(in text: String) -> Int? {
        let s = preclean(text).lowercased()
        // "pour 4 personnes", "4 pers", "4 p"
        let patterns = [
            #"(?i)\bpour\s*(\d{1,2})\s*(?:pers(?:onnes)?|p|parts?)\b"#,
            #"(?i)\b(\d{1,2})\s*(?:pers(?:onnes)?|p|parts?)\b"#
        ]
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p),
               let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let rg = Range(m.range(at: 1), in: s) {
                return Int(s[rg])
            }
        }
        return nil
    }

    // MARK: - Heuristiques ultra-simples

    private static func preclean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // Fraction unicode -> ascii
        s = s.replacingOccurrences(of: "½", with: "1/2")
             .replacingOccurrences(of: "¼", with: "1/4")
             .replacingOccurrences(of: "¾", with: "3/4")

        // Points spéciaux, puces, tirets exotiques
        s = s.replacingOccurrences(of: "’", with: "'")
             .replacingOccurrences(of: "–", with: "-")
             .replacingOccurrences(of: "—", with: "-")
             .replacingOccurrences(of: "•", with: "-")
             .replacingOccurrences(of: "◦", with: "-")

        // "400g" -> "400 g" pour aider le LLM
        s = s.replacingOccurrences(of: #"(?i)(\d)([a-z])"#, with: "$1 $2", options: .regularExpression)

        // Supprimer déco en tête ("- ", "* ", "• ", "(1) "…)
        s = s.replacingOccurrences(of: #"^[\s\-\*\•\·\(\)\d]{0,3}"#, with: "", options: .regularExpression)

        // Condenser espaces
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return s
    }

    /// Fusion très simple: si la ligne est très courte ou commence par "de/d'/du/des" ou par une minuscule,
    /// on la rattache à la précédente (ça casse le moins de choses et évite "oigno" / "n").
    private static func mergeWrappedLines(_ lines: [String]) -> [String] {
        var out: [String] = []
        for line in lines {
            let l = line
            let isTiny = l.count <= 3
            let startsConnector = l.hasPrefix("de ") || l.hasPrefix("d'") || l.hasPrefix("du ") || l.hasPrefix("des ")
            let startsLower = l.range(of: #"^[a-zàâäéèêëîïôöùûüç]"#, options: .regularExpression) != nil

            if var last = out.last, (isTiny || startsConnector || startsLower) {
                if last.hasSuffix("-") { last.removeLast() } // casse-mot
                out[out.count - 1] = last + " " + l
            } else {
                out.append(l)
            }
        }
        return out
    }

    private static func startsWithNumber(_ s: String) -> Bool {
        s.range(of: #"^\s*\d"#, options: .regularExpression) != nil
    }

    private static func startsWithBullet(_ s: String) -> Bool {
        s.range(of: #"^[-\*]"#, options: .regularExpression) != nil
    }

    private static func containsKnownUnit(_ s: String) -> Bool {
        // Mini lexique seulement pour le tri (pas de normalisation ici)
        let units: Set<String> = ["g","kg","mg","ml","cl","l","cs","cac",
                                  "sachet","gousse","pincee","tranche",
                                  "boite","brique","oeuf","oeufs"]
        for tok in s.split(separator: " ") {
            if units.contains(tok.replacingOccurrences(of: ".", with: "")) { return true }
        }
        return false
    }

    private static func isInstruction(_ s: String) -> Bool {
        // Vocabulaire de cuisine le plus fréquent = on jette
        let verbs = ["prechauffer","melanger","ajouter","cuire","battre","incorporer","laisser",
                     "verser","fouetter","emincer","revenir","cuisson","four","thermostat","min","°c","etape"]
        for v in verbs where s.contains(v) { return true }
        return false
    }

    private static func isMeta(_ s: String) -> Bool {
        // Portions, titres, etc.
        if s.contains("personne") || s.contains("pers") { return true }
        if s.hasPrefix("ingrédient") || s.hasPrefix("ingredients") { return true }
        return false
    }

    private static func wordish(_ s: String) -> Bool {
        // Au moins 1 espace et 1 lettre → probablement un nom d'aliment composé
        let letters = s.replacingOccurrences(of: #"[^a-zA-Zàâäéèêëîïôöùûüç]"#,
                                             with: "",
                                             options: .regularExpression)
        return letters.count >= 3 && s.contains(" ")
    }
}
