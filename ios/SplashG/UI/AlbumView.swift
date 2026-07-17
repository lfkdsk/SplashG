import SwiftUI
import Kingfisher

struct AlbumView: View {
    let album: Album
    var onPhotoTap: ([Photo], Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cover
                info
                MasonryGrid(items: album.photos, columns: 2, spacing: 12, aspect: \.aspect) { photo in
                    PhotoCard(photo: photo) {
                        if let idx = album.photos.firstIndex(of: photo) {
                            onPhotoTap(album.photos, idx)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .contentMargins(.bottom, 40, for: .scrollContent)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(1.5, contentMode: .fit)
            .overlay {
                KFImage(album.coverThumbURL)
                    .placeholder { Rectangle().fill(Theme.card) }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .overlay(
                LinearGradient(colors: [.clear, Theme.bg.opacity(0.9)],
                               startPoint: .center, endPoint: .bottom)
            )
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(album.title)
                .font(.title2.bold())
            if let subtitle = album.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtle)
            }
            HStack(spacing: 6) {
                if let dateString = album.dateString {
                    Text(dateString)
                }
                Text("·")
                Text("\(album.photos.count) photos")
                Text("·")
                Text("Curated by \(album.curatorName ?? album.curator)")
            }
            .font(.caption)
            .foregroundStyle(Theme.subtle)
            if album.location != nil {
                Label("Location attached", systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(Theme.subtle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}
