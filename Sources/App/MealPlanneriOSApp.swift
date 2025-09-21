import SwiftUI

@main
struct MealPlannerApp: App {
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
