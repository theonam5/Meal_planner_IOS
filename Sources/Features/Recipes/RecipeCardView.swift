import SwiftUI

struct RecipeCardView: View {
    let name: String
    let type: String
    let photoPath: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: ImageURLBuilder.recetteURL(from: photoPath)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.18), AppTheme.accentLight.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ZStack {
                        LinearGradient(
                            colors: [Color.black.opacity(0.1), Color.black.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        Image(systemName: "photo")
                            .imageScale(.large)
                            .foregroundStyle(AppTheme.textMuted)
                    }
                @unknown default:
                    Color.secondary.opacity(0.1)
                }
            }
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(type.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.18))
                    )

                Text(name)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(radius: 6)
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.001))
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(height: 240)
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
    }
}
