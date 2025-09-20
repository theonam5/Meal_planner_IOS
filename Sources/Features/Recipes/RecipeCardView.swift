import SwiftUI

struct RecipeCardView: View {
    let name: String
    let type: String
    let photoPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: ImageURLBuilder.recetteURL(from: photoPath)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                        Image(systemName: "photo")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color.secondary.opacity(0.1)
                }
            }
            // ✅ correction ici : séparer maxWidth et height
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(name)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)

            Text(type)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
 
