import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject var app: AppState
    @State private var quickText = ""
    @FocusState private var quickFocused: Bool
    @State private var suggestions: [String] = []

    private let categoryOrder = ["Épicerie","Produits frais","Surgelés","Boissons","Hygiène","Autres"]

    private var sections: [AppState.ShoppingSection] { app.buildShoppingSections() }
    private var isQuickValid: Bool {
        !quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerCard

                        if sections.isEmpty {
                            emptyState
                        } else {
                            ForEach(sectionsSorted(sections)) { section in
                                SectionCard(section: section) { item in
                                    app.toggleOrRemove(
                                        name: item.ingredientName,
                                        unit: item.unit,
                                        category: section.category
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
            }
            .navigationTitle("Courses")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ajouter rapidement")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                Button(action: addQuick) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(!isQuickValid)
                .opacity(isQuickValid ? 1 : 0.4)

                TextField("Nommer un ingrédient ou un produit…", text: $quickText)
                    .focused($quickFocused)
                    .submitLabel(.done)
                    .onSubmit { addQuick() }
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: quickText) { newValue in
                        let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        suggestions = query.count >= 2 ? app.suggestManualNames(query: query) : []
                    }
                    .font(.body)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.18), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 6)

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                quickText = suggestion
                                addQuick()
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(AppTheme.accentLight.opacity(0.2))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .mpCard()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("Ta liste de courses est vide")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary)
            Text("Ajoute des produits ou importe une recette pour générer automatiquement tes courses.")
                .font(.subheadline)
                .foregroundColor(AppTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .mpCard()
    }

    private func addQuick() {
        let trimmed = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        app.addManualQuick(trimmed)
        quickText = ""
        suggestions = []
        quickFocused = true
    }

    private func sectionsSorted(_ sections: [AppState.ShoppingSection]) -> [AppState.ShoppingSection] {
        sections.sorted { lhs, rhs in
            let leftIndex = categoryOrder.firstIndex(of: lhs.category) ?? Int.max
            let rightIndex = categoryOrder.firstIndex(of: rhs.category) ?? Int.max
            return leftIndex != rightIndex ? leftIndex < rightIndex : lhs.category < rhs.category
        }
    }
}

private struct SectionCard: View {
    let section: AppState.ShoppingSection
    let toggleAction: (AppState.ShoppingItem) -> Void

    private static let quantityFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = Locale.current.decimalSeparator
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(section.category)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(section.items.count) élément(s)")
                    .font(.caption)
                    .foregroundColor(AppTheme.textMuted)
            }

            VStack(spacing: 12) {
                ForEach(section.items) { item in
                    Button {
                        toggleAction(item)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(item.checked ? AppTheme.success : AppTheme.accent.opacity(0.5))
                                .symbolRenderingMode(.hierarchical)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.ingredientName)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .fontWeight(.medium)
                                if item.totalQuantity > 0 {
                                    Text("\(formattedQuantity(item.totalQuantity))\(item.unit.isEmpty ? "" : " \(item.unit)")")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.textMuted)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.95))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.black.opacity(0.03), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 4)
                }
            }
        }
        .mpCard()
    }

    private func formattedQuantity(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.01 {
            return String(Int(rounded))
        }
        return SectionCard.quantityFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
