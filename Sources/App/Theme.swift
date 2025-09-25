import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(red: 1.00, green: 0.54, blue: 0.24)
    static let accentLight = Color(red: 1.0, green: 0.75, blue: 0.54)
    static let success = Color(red: 0.42, green: 0.80, blue: 0.47)
    static let backgroundTop = Color(red: 0.98, green: 0.96, blue: 0.95)
    static let backgroundBottom = Color.white
    static let textPrimary = Color(red: 0.18, green: 0.18, blue: 0.18)
    static let textMuted = Color(red: 0.44, green: 0.44, blue: 0.46)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static let accentUIColor = UIColor(red: 1.00, green: 0.54, blue: 0.24, alpha: 1.0)
    private static let backgroundTopUIColor = UIColor(red: 0.98, green: 0.96, blue: 0.95, alpha: 1.0)
    private static let backgroundBottomUIColor = UIColor(white: 1.0, alpha: 1.0)
    private static let textPrimaryUIColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0)
    private static let textMutedUIColor = UIColor(red: 0.44, green: 0.44, blue: 0.46, alpha: 1.0)

    static func configureAppearances() {
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = backgroundTopUIColor
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: textPrimaryUIColor,
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold)
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: textPrimaryUIColor,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = accentUIColor

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = backgroundBottomUIColor
        tabAppearance.stackedLayoutAppearance.selected.iconColor = accentUIColor
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: accentUIColor,
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold)
        ]
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: textMutedUIColor
        ]
        tabAppearance.inlineLayoutAppearance = tabAppearance.stackedLayoutAppearance
        tabAppearance.compactInlineLayoutAppearance = tabAppearance.stackedLayoutAppearance

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().unselectedItemTintColor = textMutedUIColor
        UITabBar.appearance().tintColor = accentUIColor
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accentLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: AppTheme.accent.opacity(0.22), radius: 12, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.accent.opacity(configuration.isPressed ? 0.6 : 0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.05))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 12)
            )
    }
}

extension View {
    func mpCard(padding: CGFloat = 20) -> some View {
        modifier(CardBackground(padding: padding))
    }
}
