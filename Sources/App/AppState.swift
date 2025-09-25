import Foundation
import SwiftUI
import Supabase   // nécessaire pour SB.shared et l’appel PostgREST

@MainActor
final class AppState: ObservableObject {

    // MARK: - Données "catalogue" / DB
    @Published var ingredientsById: [Int: Ingredient] = [:]
    @Published var meals: [Meal] = []
    /// Devient true quand le catalogue a été chargé avec succès (et contient au moins 1 item)
    @Published var isCatalogLoaded: Bool = false

    // MARK: - Panier de repas
    struct BasketMeal: Identifiable, Codable, Hashable {
        let id: Int        // = mealId pour unicité par recette
        let mealId: Int
        var persons: Int
    }
    @Published var basket: [BasketMeal] = [] { didSet { saveBasket() } }

    // MARK: - Etat utilisateur
    @Published var planned: [PlannedMeal] = []          // existant (ton type à toi)
    @Published var plannedRecipes: [PlannedRecipe] = [] // recettes importées (QuickImport)
@Published var importedRecipes: [ImportedRecipe] = [] // captures OCR enregistrées

    /// Items cochés (recettes: "\(ingredientId)_\(unit)"; manuels: "manual:<UUID>")
    @Published var checked: Set<String> = [] { didSet { saveChecked() } }

    /// Articles ajoutés à la volée
    @Published var manualItems: [ManualItem] = [] { didSet { saveManualItems() } }

    /// Quantité "consommée" (achetée) par groupe **côté recettes** uniquement.
    /// Clé: groupKey "name|unit|category", valeur: quantité consommée.
    @Published var consumedQtyByKey: [String: Double] = [:] { didSet { saveConsumed() } }

    // MARK: - Persistance (UserDefaults)
    private let checkedKey  = "checked_items"
    private let manualKey   = "manual_items"
    private let consumedKey = "consumed_groups"
    private let basketKey   = "basket_meals"
    // Pas de persistance pour plannedRecipes ici, car DetectedRow n'est pas Codable.

    // MARK: - Init
    init() {
        loadChecked()
        loadManualItems()
        loadConsumed()
        loadBasket()
    }

    // MARK: - Modèles pour la liste de courses
    struct ManualItem: Identifiable, Codable, Hashable {
        let id: UUID
        var ingredientId: Int?
        var name: String
        var category: String
        var unit: String        // vide si non renseigné
        var quantity: Double    // 0 par défaut pour un ajout manuel X
    }

    struct ShoppingItem: Identifiable, Hashable {
        let id: String                 // ex: "42_g" ou "manual:<uuid>"
        let ingredientId: Int?         // nil si 100% manuel
        let ingredientName: String
        let category: String
        let unit: String               // peut être vide pour un manuel
        let totalQuantity: Double      // 0 => n’affichera rien côté UI
        var checked: Bool
    }

    struct ShoppingSection: Identifiable, Hashable {
        let id = UUID()
        let category: String
        let items: [ShoppingItem]
    }

    struct ImportedRecipe: Identifiable {
        let id = UUID()
        let title: String
        let baseServings: Int
        let createdAt: Date
        var ingredients: [DetectedRow]
    }

    // MARK: - Modèle planning (QuickImport)
    struct PlannedRecipe: Identifiable {
        let id = UUID()
        let title: String
        var servings: Int
        let baseServings: Int
        let date: Date
        var ingredients: [DetectedRow]

        func scaledIngredients() -> [DetectedRow] {
            guard baseServings > 0 else { return ingredients }
            let factor = Double(servings) / Double(baseServings)
            return ingredients.map { row in
                var copy = row
                if let base = row.baseQuantity ?? row.quantity {
                    copy.quantity = base * factor
                }
                return copy
            }
        }
    }

    // MARK: - Normalisation / catégorisation (v2)

    /// Normalise une chaîne: minuscules, sans accents, ponctuation supprimée, espaces condensés.
    private func normalizeName(_ s: String) -> String {
        let stripped = s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped
    }

    /// Singularise à la hache les tokens usuels.
    private func singularize(_ t: String) -> String {
        switch t {
        case "oeufs", "œufs": return "oeuf"
        case "oeuf", "œuf":   return "oeuf"
        case "pâtes", "pates": return "pate"
        case "légumes", "legumes": return "legume"
        case "fruits": return "fruit"
        case "viandes": return "viande"
        case "yaourts": return "yaourt"
        default:
            if t.count > 3, t.hasSuffix("s") { return String(t.dropLast()) }
            if t.count > 3, t.hasSuffix("x") { return String(t.dropLast()) }
            return t
        }
    }

    /// Découpe en tokens normalisés/singularisés.
    private func tokens(_ s: String) -> [String] {
        let n = normalizeName(s)
        return n.split(separator: " ").map { singularize(String($0)) }
    }

    /// Alias (marques, abréviations) → forme canonique
    private static let ALIAS_MAP: [String: String] = [
        "choco": "chocolat",
        "nutella": "chocolat",
        "coca": "cola",
        "coca-cola": "cola",
        "yaour": "yaourt",
        "legume": "legume",
        "legumes": "legume",
        "viande": "viande",
        "viandes": "viande",
        "icetea": "ice tea"
    ]

    /// Correspondances exactes (prioritaires) sur libellé normalisé complet
    private static let EXACT_CATEGORY_MAP: [String: String] = [
        // Produits frais
        "lait": "Produits frais", "yaourt": "Produits frais", "fromage": "Produits frais",
        "beurre": "Produits frais", "oeuf": "Produits frais", "creme": "Produits frais",
        "poulet": "Produits frais", "boeuf": "Produits frais", "porc": "Produits frais",
        "jambon": "Produits frais", "steak": "Produits frais",
        "fruit": "Produits frais", "legume": "Produits frais", "viande": "Produits frais",

        // Épicerie
        "riz": "Épicerie", "pate": "Épicerie", "farine": "Épicerie",
        "sucre": "Épicerie", "sel": "Épicerie", "huile": "Épicerie", "vinaigre": "Épicerie",
        "conserve": "Épicerie", "thon": "Épicerie",
        "cafe": "Épicerie", "the": "Épicerie", "chocolat": "Épicerie", "cacao": "Épicerie",

        // Boissons
        "eau": "Boissons", "jus": "Boissons", "soda": "Boissons",
        "biere": "Boissons", "vin": "Boissons", "cola": "Boissons", "ice tea": "Boissons",

        // Surgelés
        "glace": "Surgelés", "surgele": "Surgelés",

        // Hygiène
        "shampoing": "Hygiène", "savon": "Hygiène", "dentifrice": "Hygiène",
        "papier toilette": "Hygiène", "lessive": "Hygiène"
    ]

    /// Mots-clés partiels (par token) → catégorie
    private static let KEYWORD_CATEGORY_MAP: [(Set<String>, String)] = [
        (["lait","yaourt","fromage","beurre","oeuf","creme","poulet","boeuf","porc","jambon","steak","fruit","legume","viande"], "Produits frais"),
        (["pomme","banane","poire","tomate","salade","carotte","oignon","ail","citron"], "Produits frais"),
        (["riz","pate","farine","sucre","sel","huile","vinaigre","conserve","thon","cafe","the","chocolat","cacao"], "Épicerie"),
        (["eau","jus","soda","biere","vin","cola","orangina","fanta","sprite","perrier","evian","vittel","lipton","ice","tea"], "Boissons"),
        (["glace","surgele"], "Surgelés"),
        (["shampoing","savon","dentifrice","papier","toilette","lessive","gel","douche"], "Hygiène")
    ].map { (Set($0.0), $0.1) }

    /// Alias → forme canonique
    private func applyAlias(_ s: String) -> String {
        let n = normalizeName(s)
        if let a = AppState.ALIAS_MAP[n] { return a }
        let toks = tokens(s)
        if toks.contains("ice"), toks.contains("tea") { return "ice tea" }
        return n
    }

    /// Catégorie plausible (alias + exact + tokens) ou "Autres"
    private func categorizeManual(_ rawName: String) -> String {
        let alias = applyAlias(rawName)
        if let exact = AppState.EXACT_CATEGORY_MAP[alias] { return exact }

        let toks = Set(tokens(alias))
        if toks.count == 1, let t = toks.first, let cat = AppState.EXACT_CATEGORY_MAP[t] { return cat }

        for (kwSet, cat) in AppState.KEYWORD_CATEGORY_MAP {
            if !toks.isDisjoint(with: kwSet) { return cat }
        }
        return "Autres"
    }

    /// Catégorie pour ajouts manuels. L’unité reste vide.
    private func inferCategory(for name: String) -> String {
        if let match = matchIngredient(by: name) { return match.category }
        return categorizeManual(name)
    }

    /// Suggestions d’intitulés pendant la saisie
    func suggestManualNames(query: String, limit: Int = 8) -> [String] {
        let q = normalizeName(query)
        guard !q.isEmpty else { return [] }

        // Source A: noms d’ingrédients catalogue
        var set = Set(ingredientsById.values.map { normalizeName($0.name) })

        // Source B: clés d’exact map + alias cibles
        set.formUnion(Set(AppState.EXACT_CATEGORY_MAP.keys))
        set.formUnion(Set(AppState.ALIAS_MAP.values))

        // Source C: quelques marques usuelles
        set.formUnion(["cola","ice tea"])

        // Filtrage: prefix puis substring
        let pref = set.filter { $0.hasPrefix(q) }.sorted()
        if pref.count >= limit { return Array(pref.prefix(limit)) }
        let rest = set.subtracting(pref)
            .filter { $0.contains(q) }
            .sorted()
        return (pref + rest).prefix(limit).map { String($0) }
    }

    // MARK: - Panier de repas (API)

    func addToBasket(mealId: Int, persons: Int) {
        let p = max(1, persons)
        if let idx = basket.firstIndex(where: { $0.mealId == mealId }) {
            basket[idx].persons = p
        } else {
            basket.append(BasketMeal(id: mealId, mealId: mealId, persons: p))
        }
    }

    func updateBasketPersons(mealId: Int, persons: Int) {
        guard let idx = basket.firstIndex(where: { $0.mealId == mealId }) else { return }
        basket[idx].persons = max(1, persons)
    }

    func removeFromBasket(mealId: Int) {
        basket.removeAll { $0.mealId == mealId }
    }

    func clearBasket() {
        basket.removeAll()
    }

    // MARK: - Checklist

    func toggleChecked(_ itemId: String) {
        if checked.contains(itemId) { checked.remove(itemId) } else { checked.insert(itemId) }
    }

    func toggleCheckedForGroup(name: String, unit: String, category: String) {
        let ids = allIdsFor(name: name, unit: unit, category: category)
        let anyChecked = ids.contains { checked.contains($0) }
        if anyChecked { ids.forEach { checked.remove($0) } } else { ids.forEach { checked.insert($0) } }
    }

    /// 1er tap: coche tout. 2e tap: supprime les manuels et consomme la part recettes du groupe.
    func toggleOrRemove(name: String, unit: String, category: String) {
        let key = groupKey(name: name, unit: unit, category: category)
        let ids = allIdsFor(name: name, unit: unit, category: category)
        let alreadyChecked = ids.allSatisfy { checked.contains($0) }

        if alreadyChecked {
            let totals = aggregateTotalsFromBasket()
            if let tuple = totals[key] {
                let newConsumed = (consumedQtyByKey[key] ?? 0) + tuple.recipeQty
                consumedQtyByKey[key] = min(newConsumed, tuple.recipeQty)
            }
            manualItems.removeAll { m in
                let resolved = resolvedManualProperties(for: m)
                return resolved.name.localizedCaseInsensitiveCompare(name) == .orderedSame &&
                    resolved.unit == unit &&
                    resolved.category.localizedCaseInsensitiveCompare(category) == .orderedSame
            }
            ids.forEach { checked.remove($0) }
        } else {
            ids.forEach { checked.insert($0) }
        }
    }

    /// IDs (recettes + manuels) qui correspondent à (nom, unité, catégorie)
    private func allIdsFor(name: String, unit: String, category: String) -> [String] {
        var ids: [String] = []

        // Recettes: "\(ingredientId)_\(unit)"
        for (_, ing) in ingredientsById {
            let displayName = preferredName(for: ing)
            if displayName.localizedCaseInsensitiveCompare(name) == .orderedSame,
               ing.unit == unit,
               ing.category == category {
                let candidateId = "\(ing.id)_\(unit)"
                if !ids.contains(candidateId) {
                    ids.append(candidateId)
                }
            }
        }

        for recipe in plannedRecipes {
            let scaledRows = recipe.scaledIngredients()
            for row in scaledRows where row.isSelected {
                let trimmedUnit = row.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                if let ingredientId = row.canonicalId, let ingredient = ingredientsById[ingredientId] {
                    let displayName = preferredName(for: ingredient)
                    let resolvedUnit = trimmedUnit.isEmpty ? ingredient.unit : trimmedUnit
                    let categoryName = ingredient.category
                    if displayName.localizedCaseInsensitiveCompare(name) == .orderedSame,
                       resolvedUnit == unit,
                       categoryName.localizedCaseInsensitiveCompare(category) == .orderedSame {
                        let candidateId = "\(ingredient.id)_\(resolvedUnit)"
                        if !ids.contains(candidateId) { ids.append(candidateId) }
                    }
                } else {
                    let displayName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let categoryName = inferCategory(for: displayName)
                    if displayName.localizedCaseInsensitiveCompare(name) == .orderedSame,
                       trimmedUnit == unit,
                       categoryName.localizedCaseInsensitiveCompare(category) == .orderedSame {
                        let candidateId = "planned:\(recipe.id.uuidString):\(row.id.uuidString)"
                        if !ids.contains(candidateId) { ids.append(candidateId) }
                    }
                }
            }
        }
        // Manuels: "manual:<uuid>"
        for m in manualItems {
            let resolved = resolvedManualProperties(for: m)
            if resolved.name.localizedCaseInsensitiveCompare(name) == .orderedSame,
               resolved.unit == unit,
               resolved.category.localizedCaseInsensitiveCompare(category) == .orderedSame {
                if !ids.contains(resolved.checkId) {
                    ids.append(resolved.checkId)
                }
            }
        }
        return ids
    }

    /// Clé normalisée pour les groupes (sans accents, lowercased)
    private func groupKey(name: String, unit: String, category: String) -> String {
        func norm(_ s: String) -> String {
            s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        }
        return "\(norm(name))|\(norm(unit))|\(norm(category))"
    }

    /// Affiche en priorité le nom canonique s'il est présent.
    private func preferredName(for ingredient: Ingredient) -> String {
        if let canonical = ingredient.canonicalName?.trimmingCharacters(in: .whitespacesAndNewlines), !canonical.isEmpty {
            return canonical
        }
        return ingredient.name
    }

    // MARK: - Articles manuels

    /// Ajout manuel explicite: accepte quantité 0 et unité vide.
    func addManualItem(
        name: String,
        category: String,
        unit: String,
        quantity: Double,
        ingredientId: Int? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let qty = max(0, quantity)

        if let ingredientId, let ingredient = ingredientsById[ingredientId] {
            let displayName = preferredName(for: ingredient)
            let resolvedUnit = trimmedUnit.isEmpty ? ingredient.unit : trimmedUnit
            let resolvedCategory = ingredient.category

            if let idx = manualItems.firstIndex(where: {
                $0.ingredientId == ingredientId && $0.unit == resolvedUnit
            }) {
                manualItems[idx].quantity += qty
                manualItems[idx].name = displayName
                manualItems[idx].category = resolvedCategory
            } else {
                manualItems.append(.init(
                    id: UUID(),
                    ingredientId: ingredientId,
                    name: displayName,
                    category: resolvedCategory,
                    unit: resolvedUnit,
                    quantity: qty
                ))
            }
            return
        }

        let resolvedCategory = category.isEmpty ? inferCategory(for: trimmedName) : category
        manualItems.append(.init(
            id: UUID(),
            ingredientId: nil,
            name: trimmedName,
            category: resolvedCategory,
            unit: trimmedUnit,
            quantity: qty  // 0 autorisé
        ))
    }

    /// Ajout rapide: catégorie auto, unité vide, quantité 0. "@Catégorie" supporté.
    func addManualQuick(_ rawInput: String) {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let (nameOnly, forcedCategory) = parseCategoryOverride(from: input)
        let finalCategory = forcedCategory ?? inferCategory(for: nameOnly)
        addManualItem(name: nameOnly, category: finalCategory, unit: "", quantity: 0)
    }

    func removeManualItem(id: UUID) { manualItems.removeAll { $0.id == id } }

    func updateManualItem(id: UUID, quantity: Double) {
        guard let i = manualItems.firstIndex(where: { $0.id == id }) else { return }
        manualItems[i].quantity = max(0, quantity)
    }

    func resetConsumed() { consumedQtyByKey.removeAll() }

    // MARK: - Construction de la liste de courses (via PANIER)

    private func resolvedManualProperties(for item: ManualItem) -> (name: String, category: String, unit: String, checkId: String, ingredientId: Int?) {
        if let id = item.ingredientId, let ingredient = ingredientsById[id] {
            let displayName = item.name.isEmpty ? preferredName(for: ingredient) : item.name
            let resolvedUnit = item.unit.isEmpty ? ingredient.unit : item.unit
            let category = ingredient.category
            return (displayName, category, resolvedUnit, "\(ingredient.id)_\(resolvedUnit)", ingredient.id)
        }
        return (item.name, item.category, item.unit, "manual:\(item.id.uuidString)", nil)
    }

    private func aggregateTotalsFromBasket() -> [String: (displayName: String, category: String, unit: String,
                                                          totalQty: Double, recipeQty: Double, manualQty: Double,
                                                          idsForCheck: [String], anyIngredientId: Int?, hasRecipe: Bool)] {
        var totals: [String: (String, String, String, Double, Double, Double, [String], Int?, Bool)] = [:]

        // 1) Recettes issues du panier
        let mealById = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
        for b in basket {
            guard let meal = mealById[b.mealId] else { continue }
            for comp in meal.ingredients {
                guard let ing = ingredientsById[comp.ingredientId] else { continue }
                let add = comp.qtyPerPerson * Double(b.persons)
                let name = preferredName(for: ing)
                let unit = comp.unit
                let cat = ing.category
                let key = groupKey(name: name, unit: unit, category: cat)

                var t = totals[key] ?? (name, cat, unit, 0, 0, 0, [], ing.id, false)
                t.0 = name; t.1 = cat; t.2 = unit
                t.3 += add          // total
                t.4 += add          // part recettes
                t.6.append("\(ing.id)_\(unit)")
                t.7 = ing.id
                t.8 = true
                totals[key] = t
            }
        }

        // 1bis) Recettes importées (QuickImport)
        for recipe in plannedRecipes {
            let scaledRows = recipe.scaledIngredients()
            for row in scaledRows where row.isSelected {
                let quantity = row.quantity ?? row.baseQuantity ?? 0
                let trimmedUnit = row.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                if let ingredientId = row.canonicalId, let ingredient = ingredientsById[ingredientId] {
                    let name = preferredName(for: ingredient)
                    let unit = trimmedUnit.isEmpty ? ingredient.unit : trimmedUnit
                    let category = ingredient.category
                    let key = groupKey(name: name, unit: unit, category: category)
                    var t = totals[key] ?? (name, category, unit, 0, 0, 0, [], ingredient.id, false)
                    t.0 = name; t.1 = category; t.2 = unit
                    t.3 += quantity
                    t.4 += quantity
                    let checkId = "\(ingredient.id)_\(unit)"
                    if !t.6.contains(checkId) { t.6.append(checkId) }
                    t.7 = ingredient.id
                    t.8 = true
                    totals[key] = t
                } else {
                    let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    let unit = trimmedUnit
                    let category = inferCategory(for: name)
                    let key = groupKey(name: name, unit: unit, category: category)
                    var t = totals[key] ?? (name, category, unit, 0, 0, 0, [], nil, false)
                    t.0 = name; t.1 = category; t.2 = unit
                    t.3 += quantity
                    t.4 += quantity
                    let checkId = "planned:\(recipe.id.uuidString):\(row.id.uuidString)"
                    if !t.6.contains(checkId) { t.6.append(checkId) }
                    t.8 = true
                    totals[key] = t
                }
            }
        }

        // 2) Manuels (on crée le groupe même si quantité 0 pour l’affichage)
        for m in manualItems {
            let resolved = resolvedManualProperties(for: m)
            let key = groupKey(name: resolved.name, unit: resolved.unit, category: resolved.category)
            var t = totals[key] ?? (resolved.name, resolved.category, resolved.unit, 0, 0, 0, [], resolved.ingredientId, false)
            t.0 = resolved.name; t.1 = resolved.category; t.2 = resolved.unit
            t.3 += m.quantity     // total
            t.5 += m.quantity     // part manuelle
            t.6.append(resolved.checkId)
            if let ingId = resolved.ingredientId { t.7 = ingId }
            totals[key] = t
        }

        return totals
    }

    func buildShoppingSections() -> [ShoppingSection] {
        var totals = aggregateTotalsFromBasket()

        // Appliquer la consommation côté recettes (dynamique)
        for (key, t) in totals {
            let consumed = consumedQtyByKey[key] ?? 0
            let recipeLeft = max(0, t.recipeQty - consumed)
            let newTotal = recipeLeft + t.manualQty

            // Présence d'au moins un item manuel dans ce groupe (même quantité 0)
            let hasManual = t.idsForCheck.contains { $0.hasPrefix("manual:") }

            // Ne supprime le groupe que s’il n’y a vraiment rien ET aucun item manuel
            if newTotal <= 0, recipeLeft <= 0, !hasManual, !t.hasRecipe {
                totals.removeValue(forKey: key)
            } else {
                totals[key] = (t.displayName, t.category, t.unit, newTotal, recipeLeft, t.manualQty, t.idsForCheck, t.anyIngredientId, t.hasRecipe)
            }

            // Sécurité: borne "consumed" si le panier a baissé
            if t.recipeQty < consumed {
                consumedQtyByKey[key] = t.recipeQty
            }
        }

        // Items UI
        let items: [ShoppingItem] = totals.values.map { t in
            let isChecked = t.idsForCheck.contains { checked.contains($0) }
            let primaryId = t.idsForCheck.first ?? UUID().uuidString
            return ShoppingItem(
                id: primaryId,
                ingredientId: t.anyIngredientId,
                ingredientName: t.displayName,
                category: t.category,
                unit: t.unit,
                totalQuantity: t.totalQty,   // 0 => label de quantité masqué côté vue
                checked: isChecked
            )
        }

        // Groupement + tri alphabétique
        let grouped = Dictionary(grouping: items, by: { $0.category })
        return grouped.keys.sorted().map { cat in
            let rows = grouped[cat]!.sorted {
                $0.ingredientName.localizedCaseInsensitiveCompare($1.ingredientName) == .orderedAscending
            }
            return ShoppingSection(category: cat, items: rows)
        }
    }

    // MARK: - Persistance légère

    private func loadChecked() {
        if let arr = UserDefaults.standard.array(forKey: checkedKey) as? [String] {
            checked = Set(arr)
        }
    }
    private func saveChecked() {
        UserDefaults.standard.set(Array(checked), forKey: checkedKey)
    }

    private func loadManualItems() {
        guard let data = UserDefaults.standard.data(forKey: manualKey),
              let arr = try? JSONDecoder().decode([ManualItem].self, from: data) else { return }
        manualItems = arr
    }
    private func saveManualItems() {
        if let data = try? JSONEncoder().encode(manualItems) {
            UserDefaults.standard.set(data, forKey: manualKey)
        }
    }

    private func loadConsumed() {
        if let dict = UserDefaults.standard.dictionary(forKey: consumedKey) as? [String: Double] {
            consumedQtyByKey = dict
        }
    }
    private func saveConsumed() {
        UserDefaults.standard.set(consumedQtyByKey, forKey: consumedKey)
    }

    private func loadBasket() {
        guard let data = UserDefaults.standard.data(forKey: basketKey),
              let arr = try? JSONDecoder().decode([BasketMeal].self, from: data) else { return }
        basket = arr
    }
    private func saveBasket() {
        if let data = try? JSONEncoder().encode(basket) {
            UserDefaults.standard.set(data, forKey: basketKey)
        }
    }

    // MARK: - Aide: parsing & inférence

    /// Détecte un "@Catégorie" dans la saisie, ex: "lait @Produits frais"
    private func parseCategoryOverride(from input: String) -> (name: String, category: String?) {
        let parts = input.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let category = parts[1].trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? input : name, category.isEmpty ? nil : category)
        }
        return (input, nil)
    }

    /// Cherche un ingrédient connu (catalogue) par nom approximatif
    private func matchIngredient(by name: String) -> Ingredient? {
        let target = name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if let exact = ingredientsById.values.first(where: {
            $0.name.folding(options: .diacriticInsensitive, locale: .current).lowercased() == target
        }) { return exact }
        return ingredientsById.values.first(where: {
            $0.name.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(target)
        })
    }

    // MARK: - Planning API (QuickImport)

    /// Ajoute une recette importée (titre + nb personnes + ingrédients) au "planning import".
    /// Laisse ton `planned: [PlannedMeal]` intact.
    func addImportedRecipe(title: String, baseServings: Int, ingredients: [DetectedRow], createdAt: Date = Date()) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = trimmed.isEmpty ? "Recette" : trimmed
        let base = max(1, baseServings)
        let normalizedIngredients = ingredients.map { row -> DetectedRow in
            var copy = row
            if copy.baseQuantity == nil {
                copy.baseQuantity = row.quantity
            }
            return copy
        }
        let recipe = ImportedRecipe(title: normalizedTitle, baseServings: base, createdAt: createdAt, ingredients: normalizedIngredients)
        importedRecipes.insert(recipe, at: 0)
    }

    func removeImportedRecipe(id: UUID) {
        importedRecipes.removeAll { $0.id == id }
    }

    func addPlannedRecipe(title: String, servings: Int, baseServings: Int?, ingredients: [DetectedRow], date: Date = Date()) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = t.isEmpty ? "Recette" : t
        let base = max(1, baseServings ?? servings)
        let normalizedServings = max(1, servings)
        let normalizedIngredients = ingredients.map { row -> DetectedRow in
            var copy = row
            if copy.baseQuantity == nil {
                copy.baseQuantity = row.quantity
            }
            return copy
        }
        let newEntry = PlannedRecipe(
            title: normalizedTitle,
            servings: normalizedServings,
            baseServings: base,
            date: date,
            ingredients: normalizedIngredients
        )

        var updated = plannedRecipes
        updated.append(newEntry)
        plannedRecipes = updated
    }

    func updatePlannedRecipeServings(id: UUID, servings: Int) {
        guard let index = plannedRecipes.firstIndex(where: { $0.id == id }) else { return }
        plannedRecipes[index].servings = max(1, servings)
    }

    // MARK: - Chargement catalogue (Supabase)

    /// Charge la table "ingredients" depuis Supabase et met à jour `ingredientsById` + `isCatalogLoaded`.
    /// Appelle-la au lancement de l’app (ex: dans `.task` de la vue racine).
    func refreshIngredientsFromSupabase() async {
        do {
            let response = try await SB.shared
                .from("ingredients")
                .select()       // ex: .select("id,nom,categorie_rayon,unite,nom_canon,photo_ingredient,pivot_unit")
                .execute()

            let rows = try JSONDecoder().decode([IngredientDB].self, from: response.data)
            let mapped = rows.map(Ingredient.init(db:))
            ingredientsById = Dictionary(uniqueKeysWithValues: mapped.map { ($0.id, $0) })
            isCatalogLoaded = !mapped.isEmpty

            #if DEBUG
            print("[AppState] ingredients loaded: \(ingredientsById.count)")
            #endif
        } catch {
            isCatalogLoaded = false
            #if DEBUG
            print("[AppState] Échec chargement ingrédients:", error.localizedDescription)
            #endif
        }
    }
}
