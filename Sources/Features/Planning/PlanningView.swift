import SwiftUI

// MARK: - Repas prévus (Panier) + Recettes importées (QuickImport)
struct PlanningView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationView {
            List {
                // État vide uniquement si panier ET importés sont vides
                if app.basket.isEmpty && app.plannedRecipes.isEmpty {
                    Text("Aucun repas prévu. Ajoute des recettes depuis l’onglet Recettes, ou importe depuis Import rapide.")
                        .foregroundColor(.secondary)
                }

                // Panier classique (inchangé)
                if !app.basket.isEmpty {
                    Section("Panier de recettes") {
                        ForEach(app.basket) { b in
                            if let meal = app.meals.first(where: { $0.id == b.mealId }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(meal.name).font(.headline)
                                        Text("\(b.persons) pers")
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Stepper(
                                        value: Binding(
                                            get: { b.persons },
                                            set: { app.updateBasketPersons(mealId: b.mealId, persons: $0) }
                                        ),
                                        in: 1...20
                                    ) {
                                        EmptyView()
                                    }
                                    .labelsHidden()
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        app.removeFromBasket(mealId: b.mealId)
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                // Recettes importées (QuickImport)
                if !app.plannedRecipes.isEmpty {
                    Section("Recettes importées") {
                        ForEach(app.plannedRecipes) { pr in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pr.title).font(.headline)
                                    Text("\(pr.servings) pers • \(pr.date.formatted(date: .abbreviated, time: .omitted))")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                                Spacer()
                                // Stepper qui met à jour le nombre de personnes importées
                                Stepper(
                                    value: Binding(
                                        get: { pr.servings },
                                        set: { newVal in
                                            if let idx = app.plannedRecipes.firstIndex(where: { $0.id == pr.id }) {
                                                let old = app.plannedRecipes[idx]
                                                app.plannedRecipes[idx] = .init(
                                                    title: old.title,
                                                    servings: max(1, newVal),
                                                    date: old.date,
                                                    ingredients: old.ingredients
                                                )
                                            }
                                        }
                                    ),
                                    in: 1...20
                                ) {
                                    EmptyView()
                                }
                                .labelsHidden()
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    app.plannedRecipes.removeAll { $0.id == pr.id }
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Repas prévus")
            .toolbar {
                // Bouton existant (panier)
                if !app.basket.isEmpty {
                    Button("Vider") { app.clearBasket() }
                }
                // Petit plus: vider les importés si présent
                if !app.plannedRecipes.isEmpty {
                    Button("Vider importés") { app.plannedRecipes.removeAll() }
                }
            }
        }
    }
}
