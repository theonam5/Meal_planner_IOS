import Foundation

// MARK: - Conversions DB -> App
// Ces extensions isolent la logique de mapping dans un seul endroit.
// Si ton schéma DB évolue, tu modifies ici, pas dans toutes les vues.

// Transforme un IngredientDB (DB) en Ingredient (App)
extension Ingredient {
    init(db: IngredientDB) {
        self.id = db.id
        self.name = db.nom
        self.category = db.categorie_rayon
        self.unit = db.unite
        self.photo = db.photo_ingredient
        self.canonicalName = db.nom_canon
        self.pivotUnit = db.pivot_unit
    }
}

// Transforme une RecetteDB et une liste de CompositionRecetteDB en Meal (App)
extension Meal {
    // Constructeur minimal sans ingrédients (utile si tu listes d'abord les recettes)
    init(db: RecetteDB) {
        self.id = db.id
        self.name = db.nom_recette
        self.type = db.type_recette
        self.photo = db.photo_recette
        self.ingredients = []
    }

    // Constructeur complet: on passe les compositions (ingrédients + quantités)
    init(db: RecetteDB, comps: [CompositionRecetteDB]) {
        self.id = db.id
        self.name = db.nom_recette
        self.type = db.type_recette
        self.photo = db.photo_recette
        self.ingredients = comps.map { c in
            MealIngredient(
                ingredientId: c.ingredient_id,
                unit: c.unite ?? "g",             // fallback simple
                qtyPerPerson: c.quantite_par_personne,
                pivotQtyPerPerson: c.qty_pivot_per_person
            )
        }
    }
}

// Transforme un RepasPlanifieDB en PlannedMeal (App)
extension PlannedMeal {
    init(db: RepasPlanifieDB) {
        self.id = db.id
        self.mealId = db.recette_id
        self.persons = db.nb_personnes
        self.dateISO = db.date_repas
    }
}
