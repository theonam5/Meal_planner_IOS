import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState   // ⬅️ remplace @StateObject

    var body: some View {
        TabView {
            ShoppingListView()
                .tabItem { Label("Courses", systemImage: "cart") }

            PlanningView()
                .tabItem { Label("Planning", systemImage: "calendar") }

            RecipesView()
                .tabItem { Label("Recettes", systemImage: "fork.knife") }
        }
        // ⬇️ supprime .environmentObject(app) ici (déjà injecté par l’app)
    }
}
