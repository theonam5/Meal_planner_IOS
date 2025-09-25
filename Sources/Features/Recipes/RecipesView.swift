import SwiftUI

struct RecipesView: View {
    @EnvironmentObject var app: AppState

    @State private var search = ""
    @State private var loading = false
    @State private var error: String?
    @State private var selection: ImportedSelection?

    let recipesRepo = RecipesRepository()
    let ingredientsRepo = IngredientsRepository()

    struct ImportedSelection: Identifiable {
        let recipe: AppState.ImportedRecipe
        var servings: Int
        var id: UUID { recipe.id }
    }

    private var filteredImported: [AppState.ImportedRecipe] {
        guard !search.isEmpty else { return app.importedRecipes }
        return app.importedRecipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(search) ||
            recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    private var filteredCatalog: [Meal] {
        guard !search.isEmpty else { return app.meals }
        return app.meals.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                Group {
                    if loading {
                        ProgressView().controlSize(.large)
                    } else if let error {
                        errorState(error)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 24) {
                                heroHeader
                                importedSection
                                if !filteredCatalog.isEmpty {
                                    catalogueSection
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 32)
                        }
                    }
                }
            }
            .searchable(text: $search)
            .task { await loadDataIfNeeded() }
            .sheet(item: $selection) { selection in
                ImportedRecipePlanningSheet(
                    recipe: selection.recipe,
                    initialServings: selection.servings,
                    onAdd: { servings in
                        app.addPlannedRecipe(
                            title: selection.recipe.title,
                            servings: servings,
                            baseServings: selection.recipe.baseServings,
                            ingredients: selection.recipe.ingredients
                        )
                    },
                    onDelete: {
                        app.removeImportedRecipe(id: selection.recipe.id)
                    }
                )
                .environmentObject(app)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: QuickImportView().environmentObject(app)) {
                        Image(systemName: "text.viewfinder")
                            .imageScale(.large)
                    }
                }
            }
        }
    }

    private var heroHeader: some View {
        Text("Importées")
            .font(.largeTitle.bold())
            .foregroundColor(AppTheme.textPrimary)
    }

    private var importedSection: some View {
        let imports = filteredImported
        return VStack(alignment: .leading, spacing: 16) {
            if imports.isEmpty {
                importedEmptyState
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(imports) { recipe in
                        ImportedRecipeRow(
                            recipe: recipe,
                            onSelect: {
                                selection = ImportedSelection(recipe: recipe, servings: recipe.baseServings)
                            },
                            onDelete: {
                                app.removeImportedRecipe(id: recipe.id)
                                if selection?.recipe.id == recipe.id {
                                    selection = nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var importedEmptyState: some View {
        VStack(spacing: 12) {
            if app.importedRecipes.isEmpty && search.isEmpty {
                Text("Aucune recette importée pour le moment.")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textMuted)
                Text("Utilise l’Import rapide pour scanner une recette et l’enregistrer ici.")
                    .font(.footnote)
                    .foregroundColor(AppTheme.textMuted)
                    .multilineTextAlignment(.center)
            } else {
                Text("Aucune recette importée ne correspond à ta recherche.")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textMuted)
            }
        }
        .mpCard()
    }

    private var catalogueSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Catalogue")
                .font(.title3.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)

            if filteredCatalog.isEmpty {
                catalogueEmptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(filteredCatalog) { meal in
                        NavigationLink {
                            RecipeDetailView(meal: meal)
                        } label: {
                            RecipeCardView(
                                name: meal.name,
                                type: meal.type,
                                photoPath: meal.photo
                            )
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 16)
                }
            }
        }
    }

    private var catalogueEmptyState: some View {
        VStack(spacing: 12) {
            Text("Aucune recette du catalogue ne correspond.")
                .font(.subheadline)
                .foregroundColor(AppTheme.textMuted)
        }
        .mpCard()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red.opacity(0.8))
            Text("Oups…")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(AppTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .padding(.horizontal, 20)
    }

    private func loadDataIfNeeded() async {
        guard app.meals.isEmpty else { return }
        loading = true
        defer { loading = false }

        do {
            app.ingredientsById = try await ingredientsRepo.fetchIngredientsMap()
            let recettes = try await recipesRepo.fetchRecettes()
            var built: [Meal] = []
            for recette in recettes {
                let comps = try await recipesRepo.fetchCompositions(recetteId: recette.id)
                built.append(Meal(db: recette, comps: comps))
            }
            app.meals = built
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ImportedRecipeRow: View {
    let recipe: AppState.ImportedRecipe
    let onSelect: () -> Void
    let onDelete: () -> Void

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

            Button(action: onSelect) {
                Text(recipe.title)
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .mpCard()
    }
}

private struct ImportedRecipePlanningSheet: View {
    @EnvironmentObject var app: AppState
    let recipe: AppState.ImportedRecipe
    @State private var servings: Int
    let onAdd: (Int) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(recipe: AppState.ImportedRecipe, initialServings: Int, onAdd: @escaping (Int) -> Void, onDelete: @escaping () -> Void) {
        self.recipe = recipe
        self._servings = State(initialValue: max(1, initialServings))
        self.onAdd = onAdd
        self.onDelete = onDelete
    }

    private var scaledIngredients: [DetectedRow] {
        guard recipe.baseServings > 0 else { return recipe.ingredients }
        let factor = Double(servings) / Double(recipe.baseServings)
        return recipe.ingredients.map { row in
            var copy = row
            if let base = row.baseQuantity ?? row.quantity {
                copy.quantity = base * factor
            }
            return copy
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerCard
                        stepperCard
                        ingredientsCard
                        Button {
                            onAdd(servings)
                            dismiss()
                        } label: {
                            Label("Ajouter au menu", systemImage: "menucard")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Supprimer la recette importée", systemImage: "trash")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 8)
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

            Label(recipe.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                .font(.subheadline)
                .foregroundColor(AppTheme.textMuted)
        }
        .mpCard()
    }

    private var stepperCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nombre de personnes")
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.textMuted)
            Stepper(value: $servings, in: 1...20) {
                Text("\(servings) personne(s)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
        }
        .mpCard()
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ingrédients")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary)

            if scaledIngredients.isEmpty {
                Text("Aucun ingrédient enregistré pour cette recette.")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textMuted)
            } else {
                VStack(spacing: 12) {
                    ForEach(scaledIngredients) { row in
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
            if let formatted = ImportedRecipePlanningSheet.quantityFormatter.string(from: NSNumber(value: quantity)) {
                components.append(formatted)
            } else {
                let format = quantity.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.2f"
                components.append(String(format: format, quantity))
            }
        }

        let unit = row.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unit.isEmpty {
            components.append(unit)
        }

        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    private static let quantityFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = Locale.current.decimalSeparator
        return formatter
    }()
}
