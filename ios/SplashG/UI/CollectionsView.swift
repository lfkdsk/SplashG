import SwiftUI
import Kingfisher

struct CollectionsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: GalleryStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(store.albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
                if store.albums.isEmpty && !store.loading {
                    Text("No collections yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtle)
                        .padding(.top, 120)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .refreshable {
            if let demo = Config.demoRepo {
                await store.refreshDemo(repo: demo)
            } else if let token = auth.token {
                await store.refresh(token: token)
            }
        }
    }
}

/// Cover card in the style of the MyerSplash collections list: a mosaic
/// (big cover + two more shots) with bookmark glyph and
/// "N photos · Curated by X".
struct AlbumCard: View {
    let album: Album

    /// Two extra photos for the mosaic, skipping whichever one is the cover.
    private var extras: [Photo] {
        Array(album.photos.lazy.filter { $0.thumbURL != album.coverThumbURL }.prefix(2))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            mosaic

            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .center, endPoint: .bottom)

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(album.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(album.photos.count) photos · Curated by \(album.curatorName ?? album.curator)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var mosaic: some View {
        Color.clear
            .aspectRatio(1.45, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let gap: CGFloat = 2
                    HStack(spacing: gap) {
                        if extras.count >= 2 {
                            tile(album.coverThumbURL, width: w * 0.64, height: h)
                            VStack(spacing: gap) {
                                let sw = w - w * 0.64 - gap
                                let sh = (h - gap) / 2
                                tile(extras[0].thumbURL, width: sw, height: sh)
                                tile(extras[1].thumbURL, width: sw, height: sh)
                            }
                        } else {
                            tile(album.coverThumbURL, width: w, height: h)
                        }
                    }
                }
            }
    }

    private func tile(_ url: URL?, width: CGFloat, height: CGFloat) -> some View {
        KFImage(url)
            .placeholder { Rectangle().fill(Theme.card) }
            .retry(maxCount: 2, interval: .seconds(1))
            .fade(duration: 0.25)
            .cancelOnDisappear(true)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
    }
}
