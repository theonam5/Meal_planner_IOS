import Foundation

struct OpenAIClient: LLM.Client {
    let apiKey: String
    let baseURL: URL      // ex: https://api.openai.com/v1
    let model: String     // ex: "gpt-4o-mini" ou equivalent

    // MARK: - Extraction ingredients (inchangé)
    func parseIngredients(payloadJSON: String) async throws -> LLM.Response {
        let system = """
        Tu es un parseur deterministe.
        Entree JSON: {"t": String, "s": Int?}
        - "t" = texte OCR BRUT d'une recette (titres, ingredients, etapes melanges).
        - "s" = indice portions eventuel (copie-le tel quel dans la sortie s'il est present).

        Sortie STRICTE: {"r":String?,"s":Int?,"i":[{"n":String,"q":Number?,"u":String?}],"p":[String]?}
        AUCUN TEXTE LIBRE. UNIQUEMENT CE JSON. Ne JAMAIS inventer une unite.

        TITRE ("r"):
        - Le titre est souvent la 1ere ligne sans unite ni quantite ni verbe d'action; 2..12 mots max.
        - Si aucun titre fiable, "r": null (ne pas halluciner).

        REGLES:

        1) NE GARDER QUE LES INGREDIENTS.
           Ignorer titres/en-tetes ("tarte aux pommes", "ingredients"), sections/meta ("preparation", "cuisson", "etape", "four", "°c", "min", "thermostat"),
           et phrases avec verbes d'action ("prechauffer", "melanger", "ajouter", "laisser", "cuire", "fouetter", etc.).

        2) QUANTITES (obligatoire des qu'un nombre est present):
           Accepter:
           - Decimales: "200", "200,5", "200.5"  -> virgule = point
           - Fractions: "1/2" et symboles "½","¼","¾" -> convertir
           - Mixtes: "1 1/2" -> 1.5
           - Plages: "2-3" -> moyenne (2.5)
           - Nombre colle a l'unite: "400g" -> q=400, u=g
           - Approx: "~", "env." -> ignorer l'approx, garder la valeur
           S'il y a plusieurs nombres:
             • un nombre adjacent/colle a une unite plausible est prioritaire pour q/u
             • sinon, si la ligne commence par un nombre, c'est la quantite
             • cas "piece + taille de paquet": "1 boite de 400 g de tomates" -> q=1, u="boite", n="tomates (400 g)"
           Comptables: "un/une" = 1 pour unites pieces (oeuf, gousse, sachet, tranche, boite, brique).
           "q" DOIT etre un number JSON (pas une string). "q" peut etre null si aucune quantite n'apparait.

        3) UNITES (normaliser, singulier):
           Liste autorisee: [g,kg,mg,ml,cl,l,cs,cac,oeuf,gousse,sachet,tranche,brique,pincee,boite,branche].
           Normalisation: "càs"/"cuillere a soupe" -> cs ; "cc"/"c a cafe" -> cac ; pluriels -> singulier.

        3bis) GARDE-FOU UNITES (ne JAMAIS halluciner):
           - "u" DOIT venir d’un mot explicite **dans la meme ligne** que l’ingredient, ou etre directement **colle/adjacent** au nombre (ex: "400g").
           - Interdiction de reutiliser une unite vue sur une autre ligne.
           - Unites "pieces specifiques" [oeuf, gousse, branche, tranche]:
               • u=oeuf seulement si le nom ou la ligne contient "oeuf/oeufs".
               • u=gousse seulement si la ligne contient "gousse(s)".
               • u=branche seulement si la ligne contient "branche(s)".
               • u=tranche seulement si la ligne contient "tranche(s)".
             Sinon, **u=null** (compte implicite).
           - Unites d’emballage [sachet, brique, boite] seulement si le mot est present dans la ligne.
           - En cas de doute sur l’unite, **u=null** par defaut.
           Exemples:
             "1 oignon" -> {"n":"oignon","q":1,"u":null}
             "3/4 oignon" -> {"n":"oignon","q":0.75,"u":null}
             "2 oeufs" -> {"n":"oeuf","q":2,"u":"oeuf"}
             "1 boite de 400 g de tomates" -> {"n":"tomates (400 g)","q":1,"u":"boite"}

        4) NOM ("n"):
           Retirer les articles initiaux "de/du/des/d'".
           Rester concis. Si une taille de paquet non prise comme q/u doit etre conservee, l’ajouter entre parentheses: "tomates (400 g)".

        5) SERVINGS ("s"):
           Si "s" d'entree existe -> recopier en sortie; sinon "s": null.

        6) DEDUP:
           Si deux ingredients ont meme nom normalise + meme unite, ne garder qu’un item (additionner q si evident).

        7) ETAPES ("p") (optionnel pour plus tard):
           Si des phrases d'instructions existent, retourner 3..12 etapes courtes a l'imperatif; sinon "p": null.

        8) FORMAT:
           Reponse finale = JSON compact strict: {"r":String?,"s":Int?,"i":[...],"p":[String]?}.

        EXEMPLES RAPIDES (format d'IO identique a la vraie requete):
        IN ► {"t":"Tiramisu aux fraises\\n400 g mascarpone\\n2-3 oeufs\\nenv. 25cl de creme\\nPreparation :\\nPrechauffer...", "s":null}
        OUT ► {"r":"tiramisu aux fraises","s":null,"i":[{"n":"mascarpone","q":400,"u":"g"},{"n":"oeuf","q":2.5,"u":"oeuf"},{"n":"creme","q":25,"u":"cl"}],"p":null}

        IN ► {"t":"Poulet au curry\\n1 boite de 400g de tomates pelees\\n1/2 l de lait de coco\\nSel\\nEtape 1 : couper...", "s":6}
        OUT ► {"r":"poulet au curry","s":6,"i":[{"n":"tomates pelees (400 g)","q":1,"u":"boite"},{"n":"lait de coco","q":0.5,"u":"l"},{"n":"sel","q":null,"u":null}],"p":null}
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": payloadJSON]
            ]
        ]

        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIClient", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: txt])
        }

        // Décode l’enveloppe OpenAI → extrait le JSON du message
        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let env = try JSONDecoder().decode(Envelope.self, from: data)
        guard let content = env.choices.first?.message.content.data(using: .utf8) else {
            throw NSError(domain: "OpenAIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Réponse vide"])
        }
        return try JSONDecoder().decode(LLM.Response.self, from: content)
    }

    // MARK: - Canonicalisation (nouveau)
    func canonicalize(payloadJSON: String) async throws -> LLM.CanonResponse {
        let system = """
            Tu es un mappeur deterministe d’ingredients vers un catalogue. temperature=0.
            Reponds UNIQUEMENT en json valide (objet racine), sans texte hors du json. (mot-cle: json)

            ENTREE (schema strict):
            {
              "items": [ {"n":String, "q":Number|null, "u":String|null}, ... ],
              "candidates": {
                 "0": [ {"id":Int, "name":String, "canonicalName":String|null}, ... ],
                 "1": [ ... ],
                 ...
              }
            }
            - N = longueur de items. Les cles de "candidates" sont les indices 0..N-1 sous forme de chaines.

            REGLES DE SORTIE (OBLIGATOIRES ET EXHAUSTIVES):
            - Retourne EXACTEMENT N elements dans "mapped", dans le MEME ORDRE que items (i de 0 a N-1).
            - Pour chaque i: produire {"idx":i, "canonical_id":Int|null, "canonical_name":String|null, "confidence":Number}.
            - Il doit y avoir UN et UN SEUL "mapped" par i. AUCUNE omission, AUCUN doublon, AUCUN tri.
            - Si candidates[i] est vide ou non satisfaisant: canonical_id=null, canonical_name=null, confidence<=0.5.

            CONTRAINTES:
            - Interdiction d’inventer des ids ou des noms hors candidates[i].
            - "confidence" est un reel entre 0 et 1, arrondi a 2 decimales.
            - canonical_name = candidates[i].canonicalName si present, sinon candidates[i].name (garder accents/casse du candidat).

            CRITERES D’APPARIEMENT (dans cet ordre):
            1) Egalite exacte insensible a la casse entre item.n et (canonicalName || name) -> confidence >= 0.95.
            2) Sinon, comparer des tokens normalises (lowercase, sans accents, apostrophes et ponctuation supprimees, pluriels basiques enlevés):
               - ex: "huile d'olive" == "huile dolive" == "huile olive"
               - ex: "tomates concassees" ~ "tomate concassee"
               Score selon recouvrement (Jaccard) des tokens.
            3) Egalite de score -> preferer le nom le plus court (plus canonique).

            NE PAS modifier "q" ni "u" ici.

            SORTIE (schema strict):
            { "mapped": [ {"idx":Int,"canonical_id":Int|null,"canonical_name":String|null,"confidence":Number}, ... ] }

            EXEMPLES MINIMAUX:
            IN:
            {"items":[{"n":"viande hachee"}],
             "candidates":{"0":[{"id":42,"name":"Boeuf hache"},{"id":99,"name":"Viande hachee"}]}}
            OUT:
            {"mapped":[{"idx":0,"canonical_id":99,"canonical_name":"Viande hachee","confidence":0.96}]}

            IN:
            {"items":[{"n":"huile d'olive"}],
             "candidates":{"0":[{"id":87,"name":"Huile dolive"},{"id":12,"name":"Huile de tournesol"}]}}
            OUT:
            {"mapped":[{"idx":0,"canonical_id":87,"canonical_name":"Huile dolive","confidence":0.92}]}
            """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": payloadJSON]
            ]
        ]

        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIClient", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: txt])
        }

        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let env = try JSONDecoder().decode(Envelope.self, from: data)
        guard let content = env.choices.first?.message.content.data(using: .utf8) else {
            throw NSError(domain: "OpenAIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Réponse vide"])
        }
        return try JSONDecoder().decode(LLM.CanonResponse.self, from: content)
    }
}
