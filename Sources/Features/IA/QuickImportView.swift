import SwiftUI
import PhotosUI
import Vision
import UIKit

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
    @State private var showCameraSheet = false
    @State private var cameraUnavailableAlert = false
    @State private var detected: [DetectedRow] = []
    @State private var detectedServings: Int? = nil
    @State private var targetServings: Int = 4
    @State private var ocrError: String?
    @State private var recipeTitle: String = ""
    @State private var isAnalyzing = false
    @State private var currentAnalysisID: UUID? = nil

    // MARK: - OCR (Vision) + Appel LLM + Canonicalisation
    private var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    private func runOCR() {
        guard let img = uiImage, let cgImage = img.cgImage else { return }
        ocrError = nil
        detected.removeAll()

        let analysisID = UUID()

        Task {
            await MainActor.run {
                self.currentAnalysisID = analysisID
                self.isAnalyzing = true
            }
            do {
                let request = VNRecognizeTextRequest { req, err in
                    if let err {
                        Task { @MainActor in
                            self.ocrError = err.localizedDescription
                            if self.currentAnalysisID == analysisID {
                                self.isAnalyzing = false
                                self.currentAnalysisID = nil
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
                                if self.currentAnalysisID == analysisID {
                                    self.isAnalyzing = false
                                    self.currentAnalysisID = nil
                                }
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
                                        confidenceThreshold: 0.8
                                    )
                                } catch {
                                    #if DEBUG
                                    if let decodingError = error as? DecodingError {
                                        print("[Canonicalizer] JSON decode failed: \(decodingError)")
                                    } else {
                                        print("[Canonicalizer] error: \(error.localizedDescription)")
                                    }
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
                                if self.currentAnalysisID == analysisID {
                                    self.isAnalyzing = false
                                    self.currentAnalysisID = nil
                                }
                            }
                        } catch {
                            await MainActor.run {
                                self.detected = []
                                self.ocrError = "Erreur LLM: \(error.localizedDescription)"
                                if self.currentAnalysisID == analysisID {
                                    self.isAnalyzing = false
                                    self.currentAnalysisID = nil
                                }
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
                    if self.currentAnalysisID == analysisID {
                        self.isAnalyzing = false
                        self.currentAnalysisID = nil
                    }
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
    private func changeServings(by delta: Int) {
        let newValue = min(max(targetServings + delta, 1), 20)
        guard newValue != targetServings else { return }
        targetServings = newValue
        applyScaling()
    }



    // MARK: - Normalisation locale
    private func normalizeRow(_ r: DetectedRow) -> DetectedRow {
        var n = r
        n.name = n.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        n.unit = n.unit.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return n
    }

    // MARK: - Actions
    private func saveImportedRecipe() {
        let chosen = detected
            .filter { $0.isSelected }
            .map { normalizeRow($0) }
            .filter { !$0.name.isEmpty }

        guard !chosen.isEmpty else { return }

        let baseServings = max(1, detectedServings ?? targetServings)
        let storedIngredients = chosen.map { row -> DetectedRow in
            var copy = row
            if copy.baseQuantity == nil {
                copy.baseQuantity = row.quantity
            }
            return copy
        }
        app.addImportedRecipe(
            title: recipeTitle.isEmpty ? "Recette" : recipeTitle,
            baseServings: baseServings,
            ingredients: storedIngredients
        )

        // Reset
        detected.removeAll()
        detectedServings = nil
        uiImage = nil
        recipeTitle = ""
        targetServings = 4
    }

    // MARK: - UI
    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    if !isLLMConfigured {
                        infoBanner
                    }

                    controlsCard
                    previewCard
                    errorBanner

                    if !detected.isEmpty {
                        detectedCard
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 20)
                .padding(.bottom, detected.isEmpty ? 60 : 120)
            }

            if isAnalyzing {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                    Text("Analyse en cours...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.95))
                )
                .shadow(color: Color.black.opacity(0.12), radius: 18, y: 10)
            }
        }
        .navigationTitle("Import rapide")
        .safeAreaInset(edge: .bottom) {
            if !detected.isEmpty {
                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 30, y: 14)
                    .padding(.horizontal, 12)
            }
        }
        .sheet(isPresented: $showCameraSheet) {
            CameraPicker { image in
                showCameraSheet = false
                if let image {
                    uiImage = image
                    runOCR()
                }
            }
        }
        .alert("Caméra indisponible", isPresented: $cameraUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Active la caméra ou utilise l’import de photos pour continuer.")
        }
        .onChange(of: selectedItem) { newItem in
            guard isLLMConfigured else {
                ocrError = "OpenAI non configuré. Ajoute OPENAI_API_KEY dans le Scheme."
                return
            }
            if let newItem {
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        uiImage = img
                        runOCR()
                    } else {
                        ocrError = "Impossible de charger l’image"
                    }
                }
            }
        }
    }

    private var infoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.yellow.opacity(0.8))
            Text("OPENAI_API_KEY manquante. Configure le Scheme > Run > Environment Variables.")
                .font(.footnote)
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.yellow.opacity(0.22))
        )
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Importer une recette")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary)

            Text("Capture une recette ou teste la démo pour voir le parsing automatique et la canonisation.")
                .font(.subheadline)
                .foregroundColor(AppTheme.textMuted)

            let disabled = !isLLMConfigured
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Importer une capture", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(LinearGradient(colors: [AppTheme.accent, AppTheme.accentLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .opacity(disabled ? 0.3 : 1)

                Button {
                    if isCameraAvailable {
                        showCameraSheet = true
                    } else {
                        cameraUnavailableAlert = true
                    }
                } label: {
                    Label("Prendre une photo", systemImage: "camera.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .opacity(disabled ? 0.3 : (isCameraAvailable ? 1 : 0.4))

                Button {
                    if let img = UIImage(named: "TestOCR") {
                        uiImage = img
                        runOCR()
                    }
                } label: {
                    Label("Image de test", systemImage: "doc.text.image")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .opacity(disabled ? 0.3 : 1)
            }
        }
        .mpCard()
    }

    @ViewBuilder
    private var previewCard: some View {
        if let uiImage {
            VStack(alignment: .leading, spacing: 16) {
                Text("Aperçu de la capture")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.textMuted)

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
            }
            .mpCard()
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let ocrError {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.red.opacity(0.8))
                Text("Erreur : \(ocrError)")
                    .font(.footnote)
                    .foregroundColor(AppTheme.textPrimary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
        }
    }

    private var detectedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Recette détectée")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer(minLength: 0)
            }

            TextField("Titre", text: $recipeTitle)
                .textInputAutocapitalization(.words)
                .font(.title3.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
                )

            if !detected.isEmpty {
                servingsControl
                    .padding(.top, 4)
            }

            if !detected.isEmpty {
                Text("Ingrédients détectés")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppTheme.textMuted)

                LazyVStack(spacing: 10) {
                    ForEach($detected) { $row in
                        IngredientRowEditor(
                            row: $row,
                            baseServings: detectedServings,
                            targetServings: targetServings,
                            onRemove: {
                                detected.removeAll { $0.id == row.id }
                            }
                        )
                    }
                }
            }
        }
        .mpCard(padding: 18)
    }

    private var servingsControl: some View {
        HStack(spacing: 8) {
            Button {
                changeServings(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(AppTheme.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.accent)
            .opacity(targetServings > 1 ? 1 : 0.3)
            .disabled(targetServings <= 1)

            Text("\(targetServings) pers")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)

            Button {
                changeServings(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(AppTheme.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.accent)
            .opacity(targetServings < 20 ? 1 : 0.3)
            .disabled(targetServings >= 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppTheme.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button(role: .destructive) {
                detected.removeAll()
                detectedServings = nil
                uiImage = nil
                ocrError = nil
                recipeTitle = ""
            } label: {
                Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(GhostButtonStyle())

            Button {
                saveImportedRecipe()
            } label: {
                let count = detected.filter { $0.isSelected && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
                Label(count > 0 ? "Enregistrer la recette (\(count))" : "Enregistrer la recette", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(detected.allSatisfy { !$0.isSelected })
            .opacity(detected.allSatisfy { !$0.isSelected } ? 0.4 : 1)
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    var onComplete: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            onComplete(image)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
            picker.dismiss(animated: true)
        }
    }
}

private struct IngredientRowEditor: View {
    @Binding var row: DetectedRow
    var baseServings: Int?
    var targetServings: Int
    var onRemove: () -> Void

    private var quantityBinding: Binding<Double?> {
        Binding<Double?>(
            get: { row.quantity },
            set: { newValue in
                row.quantity = newValue
                if let base = baseServings,
                   base > 0,
                   let value = newValue {
                    let factor = Double(targetServings) / Double(base)
                    row.baseQuantity = value / factor
                } else {
                    row.baseQuantity = newValue
                }
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Nom", text: $row.name)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.1), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    TextField("Qté", value: quantityBinding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.footnote.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.accent.opacity(0.1), lineWidth: 1)
                        )
                        .frame(width: 68)

                    TextField("Unité", text: $row.unit)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.accent.opacity(0.1), lineWidth: 1)
                        )
                        .frame(width: 64)

                    Spacer(minLength: 0)
                }
            }

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red.opacity(0.75))
                    .padding(8)
                    .background(
                        Circle().fill(Color.red.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.03), lineWidth: 0.5)
        )
    }
}


