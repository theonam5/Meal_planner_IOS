import Foundation
import Supabase

// MARK: - Accès aux données Supabase pour le MVP
// On ne charge que ce qui est nécessaire:
//  - la liste des recettes
//  - la composition (ingrédients/quantités) d'une recette
//  - la table des ingrédients (pour avoir nom/catégorie/unité) en dictionnaire par id

final class RecipesRepository {
    private let db = SB.shared.database

    /// Récupère les recettes de la table 'recettes'
    func fetchRecettes() async throws -> [RecetteDB] {
        try await db.from("recettes")
            .select("id,nom_recette,type_recette,photo_recette")
            .order("nom_recette", ascending: true)
            .execute()
            .value
    }

    /// Récupère la composition d'une recette (ingrédient, quantité par personne, unité)
    func fetchCompositions(recetteId: Int) async throws -> [CompositionRecetteDB] {
        try await db.from("composition_recette")
            .select("recette_id,ingredient_id,quantite_par_personne,unite,qty_pivot_per_person")
            .eq("recette_id", value: recetteId)
            .execute()
            .value
    }
}

final class IngredientsRepository {
    private let db = SB.shared.database

    /// Récupère tous les ingrédients et les mappe en dictionnaire [id: Ingredient]
    func fetchIngredientsMap() async throws -> [Int: Ingredient] {
        let rows: [IngredientDB] = try await db.from("ingredients")
            .select("id,nom,categorie_rayon,photo_ingredient,nom_canon,unite,pivot_unit")
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, Ingredient(db: $0)) })
    }
}
