import Foundation
import SwiftUI

// MARK: - Etat central de l'application (façon "store")
// Il contient:
// - le cache des ingrédients par id
// - les recettes (avec leurs compositions)
// - le planning des repas sélectionnés
// - la checklist (items cochés) persistant via UserDefaults
//
// Il expose aussi:
// - des méthodes pour modifier le planning
// - une méthode pour construire la liste de courses (agrégation client-side)

@MainActor
final class AppState: ObservableObject {
    // Cache d'ingrédients (clé: ingredient.id)
    @Published var ingredientsById: [Int: Ingredient] = [:]

    // Toutes les recettes disponibles (avec leurs MealIngredient)
    @Published var meals: [Meal] = []

    // Planning courant (repas sélectionnés par l'utilisateur)
    @Published var planned: [PlannedMeal] = []

    // Ensemble des items cochés dans la liste de courses (clé: "\(ingredientId)_\(unit)")
    @Published var checked: Set<String> = [] {
        didSet { saveChecked() }
    }

    // Clé UserDefaults pour persister la checklist
    private let checkedKey = "checked_items"

    init() { loadChecked() }

    // MARK: - Actions Planning

    /// Ajoute un repas au planning local (MVP: pas d'appel réseau ou ajout direct dans la BDD)
    /// - Parameters:
    ///   - mealId: identifiant de la recette
    ///   - persons: nombre de personnes
    ///   - dateISO: date ISO (par défaut aujourd'hui en dur pour MVP)
    func addToPlanning(mealId: Int, persons: Int, dateISO: String = "2025-09-14") {
        // Génère un nouvel id local basé sur le max existant (MVP)
        let newId = (planned.map { $0.id }.max() ?? 0) + 1
        planned.append(PlannedMeal(id: newId, mealId: mealId, persons: persons, dateISO: dateISO))
    }

    /// Retire un repas du planning
    func removeFromPlanning(_ item: PlannedMeal) {
        planned.removeAll { $0.id == item.id }
    }

    /// Met à jour le nombre de personnes pour un repas planifié
    func updatePersons(for item: PlannedMeal, persons: Int) {
        guard let idx = planned.firstIndex(of: item) else { return }
        planned[idx].persons = max(1, persons)
    }

    /// Inverse l'état "coché" d'un item de la liste de courses
    func toggleChecked(_ itemId: String) {
        if checked.contains(itemId) { checked.remove(itemId) } else { checked.insert(itemId) }
    }

    // MARK: - Construction de la liste de courses (agrégation client)

    /// Représente une ligne de la liste de courses prête pour l'UI
    struct ShoppingItem: Identifiable, Hashable {
        var id: String { "\(ingredientId)_\(unit)" } // identifiant unique combinant ingrédient et unité
        let ingredientId: Int
        let ingredientName: String
        let category: String
        let unit: String
        let totalQuantity: Double
        var checked: Bool
    }

    /// Section de la liste de courses (groupée par catégorie de rayon)
    struct ShoppingSection: Identifiable, Hashable {
        let id = UUID()
        let category: String
        let items: [ShoppingItem]
    }

    /// Agrège les quantités nécessaires à partir du planning courant.
    /// Stratégie MVP:
    /// - Récupère chaque PlannedMeal
    /// - Pour chaque MealIngredient de la recette, calcule qty = qtyPerPerson * persons
    /// - Somme par (ingredientId, unit)
    /// - Groupe par catégorie d'ingrédient
    func buildShoppingSections() -> [ShoppingSection] {
        // Index recettes par id pour résolution rapide
        let mealById = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })

        // Dictionnaire d'agrégation:
        //   key = "\(ingredientId)_\(unit)"
        //   value = tuple (id, nom ingrédient, catégorie, unité, quantité agrégée)
        var totals: [String: (ingredientId: Int, name: String, category: String, unit: String, qty: Double)] = [:]

        // Parcours des repas planifiés
        for p in planned {
            guard let meal = mealById[p.mealId] else { continue }
            for comp in meal.ingredients {
                guard let ing = ingredientsById[comp.ingredientId] else { continue }
                // Quantité pour ce repas = qtyParPersonne * nbPers
                let add = comp.qtyPerPerson * Double(p.persons)
                let key = "\(ing.id)_\(comp.unit)"
                let prev = totals[key]?.qty ?? 0
                totals[key] = (ing.id, ing.name, ing.category, comp.unit, prev + add)
            }
        }

        // Transformation en items UI
        let items = totals.values.map { t in
            ShoppingItem(
                ingredientId: t.ingredientId,
                ingredientName: t.name,
                category: t.category,
                unit: t.unit,
                totalQuantity: t.qty,
                checked: checked.contains("\(t.ingredientId)_\(t.unit)")
            )
        }

        // Groupement par catégorie de rayon
        let grouped = Dictionary(grouping: items, by: { $0.category })
        // Tri alphabétique des catégories puis des ingrédients
        return grouped.keys.sorted().map { cat in
            let rows = grouped[cat]!.sorted { $0.ingredientName < $1.ingredientName }
            return ShoppingSection(category: cat, items: rows)
        }
    }

    // MARK: - Persistance minimale de la checklist

    private func loadChecked() {
        if let arr = UserDefaults.standard.array(forKey: checkedKey) as? [String] {
            checked = Set(arr)
        }
    }

    private func saveChecked() {
        UserDefaults.standard.set(Array(checked), forKey: checkedKey)
    }
}
