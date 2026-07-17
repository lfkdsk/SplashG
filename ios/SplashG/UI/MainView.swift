import SwiftUI
import Kingfisher

enum MainTab: String, CaseIterable {
    case feed = "Feed"
    case random = "Random"
    case collections = "Collections"

    var icon: String {
        switch self {
        case .feed: return "photo.on.rectangle.angled"
        case .random: return "shuffle"
        case .collections: return "square.stack"
        }
    }
}

/// Context for the full-screen photo pager.
struct PhotoDetailContext: Identifiable {
    let id = UUID()
    let photos: [Photo]
    let index: Int
}

struct MainView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: GalleryStore

    @State private var tab: MainTab = Config.demoTab.flatMap { name in
        MainTab.allCases.first { $0.rawValue.lowercased() == name.lowercased() }
    } ?? .feed
    @State private var showSearch = false
    @State private var showProfile = false
    @State private var showDownloads = false
    @State private var detail: PhotoDetailContext?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(Theme.bg.ignoresSafeArea())
            .overlay(alignment: .bottom) { tabBar }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Album.self) { album in
                AlbumView(album: album, onPhotoTap: { photos, index in
                    detail = PhotoDetailContext(photos: photos, index: index)
                })
            }
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(onPhotoTap: { photos, index in
                detail = PhotoDetailContext(photos: photos, index: index)
            })
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showDownloads) {
            DownloadsView()
        }
        .fullScreenCover(item: $detail) { ctx in
            PhotoDetailView(photos: ctx.photos, initialIndex: ctx.index)
        }
        .task {
            if let demo = Config.demoRepo {
                await store.refreshDemo(repo: demo)
            } else if let token = auth.token {
                await store.refreshIfStale(token: token)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(tab.rawValue)
                .font(.title2.bold())
            if store.loading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 8)
            }
            Spacer()
            Button {
                showDownloads = true
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.subtle)
            }
            .padding(.trailing, 10)
            Button {
                showProfile = true
            } label: {
                avatar
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = auth.me?.avatarUrl, let url = URL(string: urlString) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.subtle)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .feed:
            FeedView(onPhotoTap: { photos, index in
                detail = PhotoDetailContext(photos: photos, index: index)
            }, onOpenProfile: { showProfile = true })
        case .random:
            RandomView(onPhotoTap: { photos, index in
                detail = PhotoDetailContext(photos: photos, index: index)
            })
        case .collections:
            CollectionsView()
        }
    }

    // MARK: Floating tab bar

    private var tabBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(MainTab.allCases, id: \.self) { t in
                    tabButton(t)
                }
            }
            .padding(5)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))

            Button {
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
            }
            .foregroundStyle(.white)
        }
        .padding(.bottom, 8)
    }

    private func tabButton(_ t: MainTab) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { tab = t }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: t.icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(t.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 74, height: 46)
            .background(
                Capsule().fill(tab == t ? Color.white.opacity(0.14) : .clear)
            )
            .foregroundStyle(tab == t ? Theme.accent : Theme.subtle)
        }
    }
}
