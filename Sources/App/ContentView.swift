import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState   // ⬅️ remplace @StateObject

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            TabView {
                RecipesView()
                    .tabItem {
                        Label("Recettes", systemImage: "fork.knife")
                            .font(.system(size: 12, weight: .semibold))
                    }

                PlanningView()
                    .tabItem {
                        Label("Mon menu", systemImage: "menucard")
                            .font(.system(size: 12, weight: .semibold))
                    }

                ShoppingListView()
                    .tabItem {
                        Label("Courses", systemImage: "cart")
                            .font(.system(size: 12, weight: .semibold))
                    }
            }
            .tint(AppTheme.accent)
        }
        // ⬇️ supprime .environmentObject(app) ici (déjà injecté par l’app)
    }
}
