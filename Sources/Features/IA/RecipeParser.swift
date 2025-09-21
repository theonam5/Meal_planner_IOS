import Foundation

struct DetectedRow: Identifiable {
    let id = UUID()
    var isSelected: Bool = true
    var name: String
    var unit: String
    var quantity: Double?
    var baseQuantity: Double?
}

enum RecipeParser {

    /// LLM-only: envoie le TEXTE OCR BRUT au LLM.
    /// Payload: {"t": String, "s": Int?}
    /// Retourne le titre détecté (si dispo), les lignes mappées et le nombre de personnes.
    static func parseWithLLM(from ocrText: String,
                             using client: any LLM.Client) async throws
    -> (title: String?, rows: [DetectedRow], servings: Int?) {

        // Hint local pour les portions
        let s = detectServings(in: ocrText)

        // JSON brut → LLM
        var obj: [String: Any] = ["t": ocrText]
        if let s { obj["s"] = s }

        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        let payloadJSON = String(data: data, encoding: .utf8) ?? #"{"t":""}"#

        // Appel LLM
        let res = try await client.parseIngredients(payloadJSON: payloadJSON)

        // Mapping vers l’UI (+ garde-fou unités ultra conservateur)
        let mapped: [DetectedRow] = res.i.map { item in
            sanitizeUnits(
                DetectedRow(
                    isSelected: true,
                    name: item.n.trimmingCharacters(in: .whitespacesAndNewlines),
                    unit: normalizeUnit(item.u ?? ""),
                    quantity: item.q,
                    baseQuantity: item.q
                )
            )
        }

        // Titre renvoyé par le LLM (si disponible)
        let title = res.r?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Si le LLM n’a pas renvoyé "s", on garde le hint local
        return (title, mapped, res.s ?? s)
    }

    /// Fallback minimal (déprécié) : pas d'analyse, juste des noms bruts.
    @available(*, deprecated, message: "LLM-only: utilisez parseWithLLM(from:using:).")
    static func parseIngredients(from lines: [String]) -> [DetectedRow] {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map {
                DetectedRow(isSelected: true, name: $0, unit: "", quantity: nil, baseQuantity: nil)
            }
    }

    /// Détection simple du nombre de portions dans du texte brut.
    static func detectServings(in text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)\bpour\s*(\d{1,2})\s*(?:pers(?:onnes)?|p|parts?)\b"#,
            #"(?i)\b(\d{1,2})\s*(?:pers(?:onnes)?|p|parts?)\b"#,
            #"(?i)\b(\d{1,2})\s*personnes\b"#,
            #"(?i)\b(\d{1,2})\s*p\b"#
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

    // MARK: - Normalisation & garde-fou unités

    private static func normalizeUnit(_ raw: String) -> String {
        let x = raw
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch x {
        case "cas","cs","cuillere a soupe","cuil a soupe": return "cs"
        case "cac","cc","cuil a cafe": return "cac"
        case "g","gr","gramme","grammes": return "g"
        case "kg": return "kg"
        case "mg": return "mg"
        case "ml": return "ml"
        case "cl": return "cl"
        case "l","litre","litres": return "l"
        case "oeuf","oeufs": return "oeuf"
        case "gousse","gousses": return "gousse"
        case "sachet","sachets": return "sachet"
        case "tranche","tranches": return "tranche"
        case "brique","briques": return "brique"
        case "pincee","pincees": return "pincee"
        case "boite","boites": return "boite"
        case "branche","branches": return "branche"
        case "": return ""
        default: return x
        }
    }

    /// Vide l’unité si elle est incohérente avec le nom (ex: u=oeuf pour "oignon").
    private static func sanitizeUnits(_ r: DetectedRow) -> DetectedRow {
        var row = r
        let name = row.name
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        func containsAny(_ keys: [String]) -> Bool {
            keys.contains { name.contains($0) }
        }

        // Unités "pièces spécifiques": valides seulement si le nom les implique
        if row.unit == "oeuf" && !containsAny(["oeuf","oeufs"]) { row.unit = "" }
        if row.unit == "gousse" && !containsAny(["gousse","ail","vanille"]) { row.unit = "" }
        if row.unit == "branche" && !containsAny(["branche","celeri","thym","romarin","persil","menthe","coriandre"]) { row.unit = "" }
        if row.unit == "tranche" && !containsAny(["tranche","jambon","pain","fromage","saumon","bacon"]) { row.unit = "" }

        // Emballages: conservent l’unité si plausibles; sinon on laisse tel quel (le prompt évite déjà l’hallucination)
        return row
    }
}
