import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()

    var body: some View {
        TabView {
            // 1) Page d'accueil: la liste de courses
            ShoppingListView()
                .tabItem { Label("Courses", systemImage: "cart") }

            // 2) Planning (repas prévus)
            PlanningView()
                .tabItem { Label("Planning", systemImage: "calendar") }

            // 3) Recettes (catalogue)
            RecipesView()
                .tabItem { Label("Recettes", systemImage: "fork.knife") }
        }
        .environmentObject(app)
    }
}
