import SwiftUI

// MARK: - Repas prévus (Panier) + Recettes importées (QuickImport)
struct PlanningView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedRecipe: AppState.PlannedRecipe? = nil


    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        if app.basket.isEmpty && app.plannedRecipes.isEmpty {
                            emptyState
                        }

                        if !app.basket.isEmpty {
                            sectionHeader(title: "Panier de recettes", icon: "bag.fill")
                            VStack(spacing: 16) {
                                ForEach(app.basket) { basket in
                                    if let meal = app.meals.first(where: { $0.id == basket.mealId }) {
                                        BasketCard(meal: meal, persons: basket.persons) { newValue in
                                            app.updateBasketPersons(mealId: basket.mealId, persons: newValue)
                                        } onRemove: {
                                            app.removeFromBasket(mealId: basket.mealId)
                                        }
                                    }
                                }
                            }
                        }

                        if !app.plannedRecipes.isEmpty {
                            VStack(spacing: 16) {
                                ForEach(app.plannedRecipes) { recipe in
                                    ImportedRecipeCard(
                                        recipe: recipe,
                                        onShowDetail: { selectedRecipe = recipe },
                                        onRemove: {
                                            app.plannedRecipes.removeAll { $0.id == recipe.id }
                                            if selectedRecipe?.id == recipe.id {
                                                selectedRecipe = nil
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                }
            }
            .navigationTitle("Repas prévus")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !app.basket.isEmpty || !app.plannedRecipes.isEmpty {
                        Menu {
                            if !app.basket.isEmpty {
                                Button(role: .destructive) {
                                    app.clearBasket()
                                } label: {
                                    Label("Vider le panier", systemImage: "bag")
                                }
                            }

                            if !app.plannedRecipes.isEmpty {
                                Button(role: .destructive) {
                                    app.plannedRecipes.removeAll()
                                    selectedRecipe = nil
                                } label: {
                                    Label("Vider les importés", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .imageScale(.large)
                                .foregroundColor(AppTheme.accent)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedRecipe) { recipe in
            ImportedRecipeDetailView(recipe: recipe)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "menucard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("Rien de prévu pour l’instant")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary)
            Text("Ajoute des recettes depuis l’onglet Recettes ou importe une capture pour remplir ton planning.")
                .font(.subheadline)
                .foregroundColor(AppTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .mpCard()
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.accent)
            Text(title)
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }
}

private struct BasketCard: View {
    let meal: Meal
    let persons: Int
    var onChange: (Int) -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundColor(AppTheme.accent)
                    .background(
                        Circle()
                            .fill(AppTheme.accent.opacity(0.12))
                            .frame(width: 44, height: 44)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(meal.name)
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(2)
                    Text(meal.type)
                        .font(.caption)
                        .foregroundColor(AppTheme.textMuted)
                }

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(8)
                        .background(Circle().fill(Color.red.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            Stepper(value: Binding(
                get: { persons },
                set: { onChange($0) }
            ), in: 1...20) {
                Text("\(persons) personne(s)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
        }
        .mpCard()
    }
}

private struct ImportedRecipeCard: View {
    let recipe: AppState.PlannedRecipe
    var onShowDetail: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "text.book.closed")
                .font(.title2)
                .foregroundColor(AppTheme.accent)
                .padding(10)
                .background(
                    Circle()
                        .fill(AppTheme.accent.opacity(0.12))
                )

            Button(action: onShowDetail) {
                Text(recipe.title)
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text("\(recipe.servings) pers")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .mpCard()
    }
}

private struct ImportedRecipeDetailView: View {
    let recipe: AppState.PlannedRecipe
    @Environment(\.dismiss) private var dismiss

    private static let quantityFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = Locale.current.decimalSeparator
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerCard
                        ingredientsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                }
            }
            .navigationTitle(recipe.title.isEmpty ? "Recette importée" : recipe.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.title.isEmpty ? "Recette importée" : recipe.title)
                .font(.title3.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)

            HStack(spacing: 12) {
                Label("\(recipe.servings) personne(s)", systemImage: "person.3.fill")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textMuted)
                Spacer()
                Label(recipe.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textMuted)
            }
        }
        .mpCard()
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ingrédients")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary)

            let items = recipe.scaledIngredients()
            if items.isEmpty {
                Text("Aucun ingrédient enregistré pour cette recette.")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textMuted)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.name)
                                .foregroundColor(AppTheme.textPrimary)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)

                            Spacer()

                            if let label = quantityText(for: row) {
                                Text(label)
                                    .font(.footnote.monospacedDigit())
                                    .foregroundColor(AppTheme.textMuted)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .mpCard()
    }

    private func quantityText(for row: DetectedRow) -> String? {
        var components: [String] = []

        if let quantity = row.quantity {
            if let formatted = Self.quantityFormatter.string(from: NSNumber(value: quantity)) {
                components.append(formatted)
            } else {
                components.append(String(format: quantity.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.2f", quantity))
            }
        }

        let unit = row.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unit.isEmpty {
            components.append(unit)
        }

        return components.isEmpty ? nil : components.joined(separator: " ")
    }
}
