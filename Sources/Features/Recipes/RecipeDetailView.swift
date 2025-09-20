import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject var app: AppState
    let meal: Meal

    @State private var persons: Int = 1
    @State private var showAddedToast = false
    @State private var isAdding = false

    private var computedIngredients: [(name: String, unit: String, qty: Double)] {
        meal.ingredients.compactMap { comp in
            let name = app.ingredientsById[comp.ingredientId]?.name ?? "Ingrédient #\(comp.ingredientId)"
            let qty  = comp.qtyPerPerson * Double(persons)
            return (name, comp.unit, qty)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var imageURL: URL? { ImageURLBuilder.recetteURL(from: meal.photo as? String) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ingredients
                Color.clear.frame(height: 120) // espace pour le footer sticky
            }
        }
        .navigationTitle(meal.name)
        .navigationBarTitleDisplayMode(.inline)

        // Footer sticky
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Stepper(value: $persons, in: 1...20) { EmptyView() }
                    .labelsHidden()
                Text("\(persons) pers").monospacedDigit()

                Spacer()

                Button {
                    // verrou + snapshot de l'état
                    guard !isAdding else { return }
                    let snapshotPersons = persons
                    isAdding = true

                    feedback()
                    Task { @MainActor in
                        // Idéal: rendre cette méthode async throws côté AppState
                        // et l'await ici. À défaut, garde-la sync mais le verrou reste vital.
                        await app.addToBasket(mealId: meal.id, persons: snapshotPersons)

                        withAnimation(.spring) { showAddedToast = true }
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // ~1s
                        withAnimation { showAddedToast = false }
                        isAdding = false
                    }
                } label: {
                    Label(isAdding ? "Ajout..." : "Ajouter au panier",
                          systemImage: isAdding ? "hourglass" : "cart.badge.plus")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAdding)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .top)
        }

        // Snackbar discret en bas (plus d’ovale flou)
        .overlay(alignment: .bottom) {
            if showAddedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Ajouté au panier")
                        .font(.subheadline).bold()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.85)) // opaque, pas de material, donc pas de flou
                )
                .foregroundStyle(.white)
                .padding(.bottom, 80) // au-dessus du footer
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack { Rectangle().fill(Color.secondary.opacity(0.1)); ProgressView() }
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .failure:
                            ZStack {
                                Rectangle().fill(Color.secondary.opacity(0.1))
                                Image(systemName: "photo").imageScale(.large).foregroundColor(.secondary)
                            }
                        @unknown default:
                            Rectangle().fill(Color.secondary.opacity(0.1))
                        }
                    }
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(height: 200)

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name).font(.title2).bold().foregroundStyle(.white)
                if !meal.type.isEmpty {
                    Text(meal.type).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding()
        }
        .padding(.horizontal)
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingrédients").font(.headline).padding(.bottom, 4)
            ForEach(Array(computedIngredients.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text("\(formatQty(item.qty)) \(item.unit)")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func formatQty(_ q: Double) -> String {
        if abs(q.rounded() - q) < 0.001 { return String(Int(q.rounded())) }
        return String(format: "%.2f", q).replacingOccurrences(of: ".00", with: "")
    }

    private func feedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
