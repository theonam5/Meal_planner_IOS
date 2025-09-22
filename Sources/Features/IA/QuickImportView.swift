import SwiftUI
import PhotosUI
import Vision

struct QuickImportView: View {
    @EnvironmentObject var app: AppState

    // LLM obligatoire: pas de Noop, pas de substitution silencieuse
    private let llm: (any LLM.Client)?
    private let isLLMConfigured: Bool

    // Injection explicite possible pour tests/preview, sinon auto-config via env vars
    // OPENAI_API_KEY, OPENAI_BASE_URL (facultatif), OPENAI_MODEL (facultatif)
    init(llm: (any LLM.Client)? = nil) {
        if let llm {
            self.llm = llm
            self.isLLMConfigured = true
        } else {
            let env = ProcessInfo.processInfo.environment
            let apiKey = env["OPENAI_API_KEY"] ?? ""
            let baseURLStr = env["OPENAI_BASE_URL"] ?? "https://api.openai.com/v1"
            let model = env["OPENAI_MODEL"] ?? "gpt-4.1-mini"

            if !apiKey.isEmpty, let baseURL = URL(string: baseURLStr) {
                self.llm = OpenAIClient(apiKey: apiKey, baseURL: baseURL, model: model)
                self.isLLMConfigured = true
            } else {
                self.llm = nil
                self.isLLMConfigured = false
            }
        }
    }

    @State private var selectedItem: PhotosPickerItem?
    @State private var uiImage: UIImage?
    @State private var detected: [DetectedRow] = []
    @State private var detectedServings: Int? = nil
    @State private var targetServings: Int = 4
    @State private var ocrError: String?
    @State private var recipeTitle: String = ""

    // MARK: - OCR (Vision) + Appel LLM + Canonicalisation
    @MainActor private func runOCR() {
        guard let img = uiImage, let cgImage = img.cgImage else { return }
        ocrError = nil
        detected.removeAll()

        Task {
            do {
                let request = VNRecognizeTextRequest { req, err in
                    if let err {
                        Task {
                            await MainActor.run {
                                self.ocrError = err.localizedDescription
                            }
                        }
                        return
                    }
                    let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    let fullText = lines.joined(separator: "\n")

                    // Traitements LLM + canonisation HORS MainActor
                    Task {
                        guard let client = self.llm else {
                            await MainActor.run {
                                self.ocrError = "OpenAI non configuré (OPENAI_API_KEY manquante)."
                            }
                            return
                        }

                        let localServings = RecipeParser.detectServings(in: fullText)

                        do {
                            // 1) Extraction LLM (titre, ingrédients, portions)
                            let parsed = try await RecipeParser.parseWithLLM(from: fullText, using: client)
                            var rows = parsed.rows

                            // 2) Canonicalisation seulement si on a un catalogue en mémoire
                            if !self.app.ingredientsById.isEmpty {
                                do {
                                    rows = try await Canonicalizer.canonicalize(
                                        rows: rows,
                                        catalog: self.app.ingredientsById,
                                        using: client,
                                        confidenceThreshold: 0.75
                                    )
                                } catch {
                                    #if DEBUG
                                    print("Canonicalizer error: \(error.localizedDescription)")
                                    #endif
                                }
                            } else {
                                #if DEBUG
                                print("[QuickImport] Catalogue vide: pas de canonisation.")
                                #endif
                            }

                            // 3) Mise à jour UI sur le MainActor
                            await MainActor.run {
                                self.detectedServings = parsed.servings ?? localServings
                                if let s = self.detectedServings { self.targetServings = s }
                                self.recipeTitle = parsed.title ?? self.recipeTitle
                                self.detected = rows
                                self.applyScaling()
                            }
                        } catch {
                            await MainActor.run {
                                self.detected = []
                                self.ocrError = "Erreur LLM: \(error.localizedDescription)"
                            }
                        }
                    }
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["fr-FR","en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
            } catch {
                await MainActor.run {
                    self.ocrError = "OCR échec: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Mise à l'échelle des quantités selon portions
    private func applyScaling() {
        guard let base = detectedServings, base > 0 else { return }
        let factor = Double(targetServings) / Double(base)
        for i in detected.indices {
            if let baseQ = detected[i].baseQuantity {
                detected[i].quantity = baseQ * factor
            }
        }
    }

    // MARK: - Normalisation locale
    private func normalizeRow(_ r: DetectedRow) -> DetectedRow {
        var n = r
        n.name = n.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        n.unit = n.unit.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return n
    }

    // MARK: - Actions
    private func addToShoppingList() {
        let chosen = detected
            .filter { $0.isSelected }
            .map { normalizeRow($0) }
            .filter { !$0.name.isEmpty }

        // 1) Panier
        for row in chosen {
            app.addManualItem(
                name: row.name,
                category: "",
                unit: row.unit,
                quantity: max(0, row.quantity ?? 0)
            )
        }

        // 2) Planning en même temps
        app.addPlannedRecipe(
            title: recipeTitle.isEmpty ? "Recette" : recipeTitle,
            servings: targetServings,
            ingredients: chosen
        )

        // Reset
        detected.removeAll()
        detectedServings = nil
        uiImage = nil
        recipeTitle = ""
    }

    // MARK: - UI
    var body: some View {
        VStack(spacing: 16) {
            if !isLLMConfigured {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("OPENAI_API_KEY manquante. Configure le Scheme > Run > Environment Variables.")
                }
                .font(.footnote)
                .foregroundStyle(.yellow)
                .padding(.horizontal)
            }

            // Sélecteur d'image
            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Importer une capture", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(!isLLMConfigured)

                // Bouton debug: charge l’asset "TestOCR"
                Button {
                    if let img = UIImage(named: "TestOCR") {
                        uiImage = img
                        runOCR()
                    }
                } label: {
                    Label("Image de test", systemImage: "doc.text.image")
                }
                .buttonStyle(.bordered)
                .disabled(!isLLMConfigured)
            }

            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
                    .padding(.horizontal)
            }

            if let ocrError {
                Text("Erreur: \(ocrError)")
                    .foregroundColor(.red)
            }

            if !detected.isEmpty {
                List {
                    // Titre de recette (éditable)
                    Section("Recette") {
                        TextField("Titre", text: $recipeTitle)
                            .textInputAutocapitalization(.words)
                    }

                    // Nombre de personnes
                    Section("Nombre de personnes") {
                        Stepper(value: $targetServings, in: 1...20) {
                            Text("\(targetServings) pers.")
                        }
                        .onChange(of: targetServings) { _ in
                            applyScaling()
                        }
                    }

                    // Ingrédients
                    Section("Ingrédients détectés") {
                        ForEach($detected) { $row in
                            HStack {
                                Toggle("", isOn: $row.isSelected).labelsHidden()

                                TextField("Nom", text: $row.name)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)

                                Spacer()

                                let qtyBinding = Binding<Double?>(
                                    get: { $row.quantity.wrappedValue },
                                    set: { newValue in
                                        $row.quantity.wrappedValue = newValue
                                        if let base = detectedServings,
                                           base > 0,
                                           let q = newValue {
                                            let factor = Double(targetServings) / Double(base)
                                            row.baseQuantity = q / factor
                                        } else {
                                            row.baseQuantity = newValue
                                        }
                                    }
                                )

                                TextField("Qté", value: qtyBinding, format: .number)
                                    .frame(width: 56)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)

                                TextField("Unité", text: $row.unit)
                                    .frame(width: 60)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)

                                Button {
                                    detected.removeAll { $0.id == row.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            if !detected.isEmpty {
                HStack {
                    Button(role: .destructive) {
                        detected.removeAll()
                        detectedServings = nil
                        uiImage = nil
                        ocrError = nil
                        recipeTitle = ""
                    } label: {
                        Label("Réinitialiser", systemImage: "trash")
                    }

                    Spacer()

                    Button {
                        addToShoppingList()
                    } label: {
                        let count = detected.filter {
                            $0.isSelected && !$0.name.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty
                        }.count
                        Label("Ajouter \(count) au panier", systemImage: "cart.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(detected.allSatisfy { !$0.isSelected })
                }
                .padding()
            }
        }
        .navigationTitle("Import rapide")
        .onChange(of: selectedItem) { newItem in
            guard isLLMConfigured else {
                ocrError = "OpenAI non configuré. Ajoute OPENAI_API_KEY dans le Scheme."
                return
            }
            if let newItem {
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            self.uiImage = img
                            self.runOCR()
                        }
                    } else {
                        await MainActor.run {
                            self.ocrError = "Impossible de charger l’image"
                        }
                    }
                }
            }
        }
    }
}
