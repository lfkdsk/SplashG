import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: GalleryStore

    var onPhotoTap: ([Photo], Int) -> Void
    var onOpenProfile: () -> Void

    var body: some View {
        let photos = store.feedPhotos
        ScrollView {
            if let backendError = store.backendError {
                banner("Backend unreachable: \(backendError)")
            }
            if photos.isEmpty && !store.loading {
                emptyState
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
        .refreshable {
            if let demo = Config.demoRepo {
                await store.refreshDemo(repo: demo)
            } else if let token = auth.token {
                await store.refresh(token: token)
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
            .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.subtle)
            Text("No albums yet")
                .font(.headline)
            Text("Bind one of your gallery repos, or follow a friend to fill this feed.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
            Button(action: onOpenProfile) {
                Text("Open Profile")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(.white)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 40)
        .padding(.top, 120)
    }
}
