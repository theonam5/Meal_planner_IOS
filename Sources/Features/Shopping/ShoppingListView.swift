import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject var app: AppState
    @State private var quickText = ""
    @FocusState private var quickFocused: Bool
    @State private var suggestions: [String] = []   // 👈 nouveau

    var sections: [AppState.ShoppingSection] { app.buildShoppingSections() }

    private let categoryOrder = ["Épicerie","Produits frais","Surgelés","Boissons","Hygiène","Autres"]
    private var isQuickValid: Bool {
        !quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            List {
                // Ligne d’ajout rapide
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button(action: addQuick) {
                                Image(systemName: "plus.circle.fill")
                                    .imageScale(.large)
                                    .contentShape(Rectangle()) // zone de clic pleine
                            }
                            .buttonStyle(.plain)
                            .disabled(!isQuickValid)

                            TextField("Ajouter un article…", text: $quickText)
                                .focused($quickFocused)
                                .submitLabel(.done)
                                .onSubmit { addQuick() }
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                // 👇 met à jour les suggestions quand on tape
                                .onChange(of: quickText) { newValue in
                                    let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    suggestions = q.count >= 2 ? app.suggestManualNames(query: q) : []
                                }
                        }

                        // 👇 ruban de suggestions
                        if !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(suggestions, id: \.self) { s in
                                        Button {
                                            // auto-complète puis ajoute direct
                                            quickText = s
                                            addQuick()
                                        } label: {
                                            Text(s)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.secondary.opacity(0.12))
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 2)
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(sectionsSorted(sections)) { section in
                    Section(section.category) {
                        ForEach(section.items) { item in
                            Button {
                                app.toggleOrRemove(
                                    name: item.ingredientName,
                                    unit: item.unit,
                                    category: section.category
                                )
                            } label: {
                                HStack {
                                    Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                    Text(item.ingredientName)
                                    Spacer()
                                    // Affiche la quantité uniquement si > 0
                                    if item.totalQuantity > 0 {
                                        Text("\(Int(item.totalQuantity)) \(item.unit)")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Courses")
        }
    }

    private func addQuick() {
        let t = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        app.addManualQuick(t)   // crée un item manuel quantité 0, unité ""
        quickText = ""
        suggestions = []        // 👈 nettoie les suggestions
        quickFocused = true     // garde le focus pour enchaîner les ajouts
    }

    private func sectionsSorted(_ sections: [AppState.ShoppingSection]) -> [AppState.ShoppingSection] {
        sections.sorted { a, b in
            let ia = categoryOrder.firstIndex(of: a.category) ?? Int.max
            let ib = categoryOrder.firstIndex(of: b.category) ?? Int.max
            return ia != ib ? ia < ib : a.category < b.category
        }
    }
}
