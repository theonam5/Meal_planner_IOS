import SwiftUI

@main
struct MealPlanneriOSApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()              // <- c'est BIEN ContentView
                .environmentObject(app)
        }
    }
}
