import Foundation

// MARK: - Modèles orientés UI/métier (côté app).
// Ici on choisit des noms en anglais/simple pour l’interface, indépendants du schéma DB.
// On évite d'exposer snake_case dans tout le code UI.

// Représentation d’un ingrédient côté app
struct Ingredient: Identifiable, Hashable {
    let id: Int
    // Nom affiché de l’ingrédient
    let name: String
    // Catégorie de rayon (texte brut, ex: "Épicerie")
    let category: String
    // Unité par défaut (ex: "g")
    let unit: String
    // Chemin/URL relative d'image (optionnel)
    let photo: String?
    // Nom canonique (optionnel)
    let canonicalName: String?
    // Unité pivot (optionnel)
    let pivotUnit: String?
}

// Lien entre un ingrédient et une recette, avec la quantité par personne
struct MealIngredient: Hashable {
    let ingredientId: Int      // on garde seulement l'id, on résoudra via un dictionnaire côté app
    let unit: String           // unité pour cet ingrédient dans CETTE recette
    let qtyPerPerson: Double   // quantité par personne
    let pivotQtyPerPerson: Double? // si tu utilises des conversions serveur
}

// Représentation d’une recette côté app, avec la liste de ses ingrédients
struct Meal: Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String
    let photo: String?
    let ingredients: [MealIngredient]
}

// Élément de planning (un repas prévu, pour X personnes, à une date)
struct PlannedMeal: Identifiable, Hashable {
    let id: Int        // dans le MVP, on peut autoincrémenter localement
    let mealId: Int
    var persons: Int
    let dateISO: String
}
