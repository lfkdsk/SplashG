import SwiftUI

struct RandomView: View {
    @EnvironmentObject private var store: GalleryStore
    var onPhotoTap: ([Photo], Int) -> Void

    @State private var photos: [Photo] = []

    var body: some View {
        ScrollView {
            if photos.isEmpty && !store.loading {
                Text("Nothing to shuffle yet")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtle)
                    .padding(.top, 120)
            } else {
                MasonryGrid(items: photos, columns: 2, spacing: 12, aspect: \.aspect) { photo in
                    PhotoCard(photo: photo) {
                        if let idx = photos.firstIndex(of: photo) {
                            onPhotoTap(photos, idx)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .overlay(alignment: .bottomTrailing) {
            Button {
                withAnimation { photos = store.randomPhotos(40) }
            } label: {
                Image(systemName: "dice")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
                    .foregroundStyle(.white)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 96)
        }
        .onAppear {
            if photos.isEmpty { photos = store.randomPhotos(40) }
        }
        .onChange(of: store.lastRefresh) {
            if photos.isEmpty { photos = store.randomPhotos(40) }
        }
    }
}
