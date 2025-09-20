import Foundation

// MARK: - Représentations 1:1 des tables Postgres (côté Supabase).
// Important:
// - On garde les noms des propriétés identiques aux colonnes SQL (snake_case)
//   pour éviter d'avoir à bidouiller un JSONDecoder custom.
// - Les colonnes Postgres de type USER-DEFINED (enum PG) sont mappées en String
//   pour éviter un crash si tu ajoutes de nouvelles valeurs côté DB.

// Table: recettes
struct RecetteDB: Codable, Identifiable {
    // Colonne bigserial: identifiant unique de la recette
    let id: Int
    // Nom de la recette (ex: "Pâtes au saumon")
    let nom_recette: String
    // Type de recette (USER-DEFINED PG: ex: "Perso", "Plat", etc.). On reste en String.
    let type_recette: String
    // Optionnel: chemin/URL relative vers l'image stockée (ex: "images/pates.jpg")
    let photo_recette: String?

    // CodingKeys explicites pour être 100% robustes aux renommages
    enum CodingKeys: String, CodingKey {
        case id, nom_recette, type_recette, photo_recette
    }
}

// Table: ingredients
struct IngredientDB: Codable, Identifiable {
    let id: Int
    // Nom affiché (ex: "Pâtes")
    let nom: String
    // Catégorie de rayon (USER-DEFINED PG). On garde String (ex: "Épicerie")
    let categorie_rayon: String
    // Optionnel: chemin/URL relative d'une image pour l'ingrédient
    let photo_ingredient: String?
    // Nom canonique (pour regroupements/normalisation). Optionnel.
    let nom_canon: String?
    // Unité par défaut pour l'ingrédient (USER-DEFINED PG). String (ex: "g")
    let unite: String
    // Unité pivot éventuelle pour normalisations (ex: "g", "ml", "piece")
    let pivot_unit: String?

    enum CodingKeys: String, CodingKey {
        case id, nom, categorie_rayon, photo_ingredient, nom_canon, unite, pivot_unit
    }
}

// Table: composition_recette
// Décrit, pour une recette donnée, quels ingrédients et quantités par personne utiliser.
struct CompositionRecetteDB: Codable {
    // FK vers recettes.id
    let recette_id: Int
    // FK vers ingredients.id
    let ingredient_id: Int
    // Quantité par personne (Double pour gérer décimales)
    let quantite_par_personne: Double
    // Unité spécifique (USER-DEFINED PG), peut être nil si on utilise l'unité de l'ingrédient
    let unite: String?
    // Quantité par personne exprimée dans une unité pivot (si tu veux des conversions server-side)
    let qty_pivot_per_person: Double?

    enum CodingKeys: String, CodingKey {
        case recette_id, ingredient_id, quantite_par_personne, unite, qty_pivot_per_person
    }
}

// Table: repas_planifies
// Ce que l'utilisateur a prévu de cuisiner et pour combien de personnes, à une date donnée.
struct RepasPlanifieDB: Codable, Identifiable {
    let id: Int
    // FK vers recettes.id
    let recette_id: Int
    // Nombre de personnes
    let nb_personnes: Int
    // Date du repas (type date). On la prend en String ISO "YYYY-MM-DD" pour simplicité MVP.
    let date_repas: String
    // Timestamp de création (optionnel)
    let cree_le: String?
    // Slot "dinner"/"lunch" etc. (optionnel)
    let slot: String?
    // Valeur par défaut de personnes si tu en gères (optionnel)
    let default_nb_pers: Int?

    enum CodingKeys: String, CodingKey {
        case id, recette_id, nb_personnes, date_repas, cree_le, slot, default_nb_pers
    }
}
