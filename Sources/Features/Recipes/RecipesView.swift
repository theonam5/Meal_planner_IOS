import SwiftUI

// MARK: - Liste des recettes avec grandes photos défilantes
struct RecipesView: View {
    @EnvironmentObject var app: AppState

    // Etat local: recherche, chargement, erreur
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?

    // Dépendances data
    let recipesRepo = RecipesRepository()
    let ingredientsRepo = IngredientsRepository()

    // Filtrage local par nom
    var filtered: [Meal] {
        if search.isEmpty { return app.meals }
        return app.meals.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationView {
            Group {
                if loading {
                    ProgressView().controlSize(.large)
                } else if let err = error {
                    VStack(spacing: 8) {
                        Text("Erreur").font(.headline)
                        Text(err).foregroundColor(.red).multilineTextAlignment(.center)
                    }.padding()
                } else {
                    // ICI: remplacement de la List par un ScrollView + LazyVStack
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(filtered) { meal in
                                NavigationLink {
                                    RecipeDetailView(meal: meal)
                                } label: {
                                    RecipeCardView(
                                        name: meal.name,
                                        type: meal.type,
                                        photoPath: meal.photo    // <- path en DB
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                            }
                            Color.clear.frame(height: 8) // petit espace bas
                        }
                    }
                }
            }
            .task { await loadDataIfNeeded() }              // charge au premier affichage
            .searchable(text: $search)                      // recherche en haut
            .navigationTitle("Recettes")
        }
    }

    /// Charge ingrédients, recettes, compositions si pas encore en mémoire.
    private func loadDataIfNeeded() async {
        guard app.meals.isEmpty else { return } // déjà chargé
        loading = true
        defer { loading = false }

        do {
            // 1) Cache ingrédients: dictionnaire [id: Ingredient]
            app.ingredientsById = try await ingredientsRepo.fetchIngredientsMap()

            // 2) Recettes (DB)
            let recettes = try await recipesRepo.fetchRecettes()

            // 3) Pour chaque recette, charger ses compositions puis mapper vers Meal
            var built: [Meal] = []
            for r in recettes {
                let comps = try await recipesRepo.fetchCompositions(recetteId: r.id)
                built.append(Meal(db: r, comps: comps))
            }
            app.meals = built
        } catch {
            self.error = error.localizedDescription
        }
    }
}
