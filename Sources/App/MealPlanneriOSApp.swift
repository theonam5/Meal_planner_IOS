import SwiftUI

@main
struct MealPlannerApp: App {
    init() {
        AppTheme.configureAppearances()
    }

    @StateObject var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .task {
                    // Charge le catalogue d’ingrédients dès le démarrage
                    await app.refreshIngredientsFromSupabase()
                }
        }
    }
}
