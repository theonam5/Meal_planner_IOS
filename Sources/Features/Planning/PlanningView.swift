import SwiftUI

// MARK: - Repas prévus (Panier)
struct PlanningView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationView {
            List {
                if app.basket.isEmpty {
                    Text("Aucun repas prévu. Ajoute des recettes depuis l’onglet Recettes.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(app.basket) { b in
                        if let meal = app.meals.first(where: { $0.id == b.mealId }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(meal.name).font(.headline)
                                    Text("\(b.persons) pers")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Stepper(value: Binding(
                                    get: { b.persons },
                                    set: { app.updateBasketPersons(mealId: b.mealId, persons: $0) }
                                ), in: 1...20) {
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
            .navigationTitle("Repas prévus")
            .toolbar {
                if !app.basket.isEmpty {
                    Button("Vider") { app.clearBasket() }
                }
            }
        }
    }
}
