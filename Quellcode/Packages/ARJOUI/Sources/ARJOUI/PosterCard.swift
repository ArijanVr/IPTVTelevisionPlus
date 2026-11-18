import SwiftUI

/// Poster mit Titel, optionalem Fortschrittsbalken und Gesehen-Haken.
struct PosterCard: View {
    let title: String
    var subtitle: String?
    let posterURL: URL?
    var fraction: Double = 0
    var isWatched = false

    #if os(tvOS)
    static let size = CGSize(width: 260, height: 390) // grid.col.poster, 2:3
    #else
    static let size = CGSize(width: 120, height: 180)
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedImage(url: posterURL, contentMode: .fill, maxPixel: 500) {
                ZStack {
                    Color.primary.opacity(0.08)
                    Image(systemName: "film").font(.arjo(.display)).foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipped()
            .reportsBackdrop(posterURL)
            .overlay(alignment: .bottom) {
                if fraction > 0, fraction < 1 {
                    ProgressView(value: fraction).padding(8).tint(Theme.glut)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .padding(8)
                        .accessibilityLabel("Gesehen")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))

            Text(title)
                .font(.arjo(.smallMedium))
                .lineLimit(2)
                .frame(width: Self.size.width, alignment: .leading)
            if let subtitle {
                Text(subtitle)
                    .font(.arjo(.small))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.size.width, alignment: .leading)
            }
        }
    }
}

extension View {
    /// Poster-Optik: auf Apple TV die Fokus-Anhebung ohne Kartenrahmen.
    func posterButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(TileButtonStyle(filled: false))
        #else
        buttonStyle(.plain)
        #endif
    }
}
