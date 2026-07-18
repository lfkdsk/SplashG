import SwiftUI
import Kingfisher

struct SearchView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: GalleryStore
    @Environment(\.dismiss) private var dismiss

    var onPhotoTap: ([Photo], Int) -> Void

    @State private var query = Config.demoQuery ?? ""
    @State private var lookedUpUser: UserProfile?
    @State private var lookingUp = false
    @State private var lookupError: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if trimmedQuery.isEmpty {
                            hint
                        } else {
                            userSection
                            albumSection
                            photoSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Album.self) { album in
                AlbumView(album: album, onPhotoTap: onPhotoTap)
            }
        }
        .onAppear { focused = true }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.subtle)
                TextField("Albums, photos, or a GitHub login", text: $query)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await lookupUser() } }
                if !query.isEmpty {
                    Button {
                        query = ""
                        lookedUpUser = nil
                        lookupError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.subtle)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Capsule().fill(Theme.card))

            Button("Cancel") { dismiss() }
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var hint: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.subtle)
            Text("Search your feed — or type a GitHub login and hit search to find a friend on SplashG.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
        .padding(.horizontal, 24)
    }

    // MARK: Users

    private var looksLikeLogin: Bool {
        trimmedQuery.range(of: "^[A-Za-z0-9-]{1,39}$", options: .regularExpression) != nil
    }

    @ViewBuilder
    private var userSection: some View {
        if looksLikeLogin || lookedUpUser != nil || lookupError != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("People")
                    .font(.headline)
                if let user = lookedUpUser {
                    UserResultCard(user: user) {
                        await toggleFollow(user)
                    }
                } else if lookingUp {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let error = lookupError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.subtle)
                } else {
                    Button {
                        Task { await lookupUser() }
                    } label: {
                        Label("Look up @\(trimmedQuery) on SplashG", systemImage: "person.crop.circle.badge.questionmark")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private func lookupUser() async {
        guard looksLikeLogin, let token = auth.token else { return }
        lookingUp = true
        lookedUpUser = nil
        lookupError = nil
        defer { lookingUp = false }
        do {
            lookedUpUser = try await SplashGAPI(token: token).user(trimmedQuery)
        } catch let err as APIError where err.status == 404 {
            lookupError = "@\(trimmedQuery) hasn't joined SplashG yet."
        } catch {
            lookupError = error.localizedDescription
        }
    }

    private func toggleFollow(_ user: UserProfile) async {
        guard let token = auth.token else { return }
        let api = SplashGAPI(token: token)
        do {
            if user.followedByMe {
                try await api.unfollow(user.login)
            } else {
                try await api.follow(user.login)
            }
            lookedUpUser = try await api.user(user.login)
            await auth.loadMe()
            await store.refresh(token: token)
        } catch {
            lookupError = error.localizedDescription
        }
    }

    // MARK: Albums

    private var matchingAlbums: [Album] {
        let q = trimmedQuery.lowercased()
        return store.albums.filter {
            $0.title.lowercased().contains(q)
                || $0.slug.lowercased().contains(q)
                || $0.curator.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var albumSection: some View {
        let albums = matchingAlbums
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Collections")
                    .font(.headline)
                ForEach(albums.prefix(5)) { album in
                    NavigationLink(value: album) {
                        HStack(spacing: 12) {
                            KFImage(album.coverThumbURL)
                                .placeholder { Rectangle().fill(Theme.card) }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(album.photos.count) photos · \(album.curatorName ?? album.curator)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.subtle)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Photos

    private var matchingPhotos: [Photo] {
        let q = trimmedQuery.lowercased()
        return store.feedPhotos.filter { $0.filename.lowercased().contains(q) }
    }

    @ViewBuilder
    private var photoSection: some View {
        let photos = Array(matchingPhotos.prefix(60))
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Photos")
                    .font(.headline)
                MasonryGrid(items: photos, columns: 2, spacing: 12, aspect: \.aspect) { photo in
                    PhotoCard(photo: photo) {
                        if let idx = photos.firstIndex(of: photo) {
                            onPhotoTap(photos, idx)
                        }
                    }
                }
            }
        }
    }
}

struct UserResultCard: View {
    let user: UserProfile
    var toggleFollow: () async -> Void

    @State private var busy = false

    var body: some View {
        HStack(spacing: 12) {
            if let urlString = user.avatarUrl, let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.subtle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name ?? user.login)
                    .font(.subheadline.weight(.semibold))
                Text("@\(user.login) · \(user.repos.count) albums · \(user.followerCount) followers")
                    .font(.caption)
                    .foregroundStyle(Theme.subtle)
            }
            Spacer()
            Button {
                busy = true
                Task {
                    await toggleFollow()
                    busy = false
                }
            } label: {
                Text(user.followedByMe ? "Following" : "Follow")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(user.followedByMe ? Theme.card : Theme.accent))
                    .foregroundStyle(.white)
            }
            .disabled(busy)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }
}
