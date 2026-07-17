import SwiftUI
import Kingfisher

/// Account sheet: identity, bound gallery repos, following list, sign out.
struct ProfileView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: GalleryStore
    @Environment(\.dismiss) private var dismiss

    @State private var following: [FeedUser] = []
    @State private var newFollowLogin = ""
    @State private var actionError: String?
    @State private var showRepoPicker = false
    @State private var showManualBind = false
    @State private var manualRepo = ""

    var body: some View {
        NavigationStack {
            List {
                identitySection
                if auth.backendError != nil {
                    Section {
                        Label(auth.backendError ?? "", systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                reposSection
                followingSection
                Section {
                    Button(role: .destructive) {
                        store.clear()
                        auth.signOut()
                        dismiss()
                    } label: {
                        Text("Sign Out")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showRepoPicker) {
                RepoPickerView { repo in
                    await bind(repo: repo.fullName, title: nil)
                }
            }
            .alert("Bind a repo", isPresented: $showManualBind) {
                TextField("owner/name", text: $manualRepo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Bind") {
                    let repo = manualRepo.trimmingCharacters(in: .whitespaces)
                    manualRepo = ""
                    Task { await bind(repo: repo, title: nil) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The repo must contain an album_template README.yml at its root.")
            }
            .alert("Something went wrong", isPresented: .init(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
            .task { await loadFollowing() }
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section {
            HStack(spacing: 14) {
                if let urlString = auth.me?.avatarUrl, let url = URL(string: urlString) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.subtle)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.me?.name ?? auth.me?.login ?? "—")
                        .font(.headline)
                    Text("@\(auth.me?.login ?? "—")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtle)
                    Text("\(auth.me?.followerCount ?? 0) followers · following \(auth.me?.following.count ?? 0)")
                        .font(.caption)
                        .foregroundStyle(Theme.subtle)
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    private var reposSection: some View {
        Section("My Albums") {
            ForEach(auth.me?.repos ?? []) { binding in
                VStack(alignment: .leading, spacing: 2) {
                    Text(binding.displayTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(binding.repo)
                        .font(.caption)
                        .foregroundStyle(Theme.subtle)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await unbind(repo: binding.repo) }
                    } label: {
                        Label("Unbind", systemImage: "trash")
                    }
                }
                .listRowBackground(Theme.card)
            }
            Menu {
                Button {
                    showRepoPicker = true
                } label: {
                    Label("Choose from my GitHub repos", systemImage: "list.bullet.rectangle")
                }
                Button {
                    showManualBind = true
                } label: {
                    Label("Enter owner/name", systemImage: "keyboard")
                }
            } label: {
                Label("Bind a gallery repo", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            .listRowBackground(Theme.card)
        }
    }

    private var followingSection: some View {
        Section("Following") {
            ForEach(following) { user in
                HStack(spacing: 12) {
                    if let urlString = user.avatarUrl, let url = URL(string: urlString) {
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.displayName)
                            .font(.subheadline)
                        Text("\(user.repos.count) albums")
                            .font(.caption)
                            .foregroundStyle(Theme.subtle)
                    }
                    Spacer()
                    Button("Unfollow") {
                        Task { await unfollow(user.login) }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.subtle)
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Theme.card)
            }

            HStack {
                TextField("GitHub login", text: $newFollowLogin)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Follow") {
                    let login = newFollowLogin.trimmingCharacters(in: .whitespaces)
                    newFollowLogin = ""
                    Task { await follow(login) }
                }
                .disabled(newFollowLogin.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
                .font(.footnote)
            }
            .listRowBackground(Theme.card)
        }
    }

    // MARK: Actions

    private func loadFollowing() async {
        guard let token = auth.token else { return }
        following = (try? await SplashGAPI(token: token).follows()) ?? []
    }

    private func bind(repo: String, title: String?) async {
        guard let token = auth.token, !repo.isEmpty else { return }
        do {
            try await SplashGAPI(token: token).bind(repo: repo, title: title)
            await auth.loadMe()
            await store.refresh(token: token)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func unbind(repo: String) async {
        guard let token = auth.token else { return }
        do {
            try await SplashGAPI(token: token).unbind(repo: repo)
            await auth.loadMe()
            await store.refresh(token: token)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func follow(_ login: String) async {
        guard let token = auth.token, !login.isEmpty else { return }
        do {
            try await SplashGAPI(token: token).follow(login)
            await auth.loadMe()
            await loadFollowing()
            await store.refresh(token: token)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func unfollow(_ login: String) async {
        guard let token = auth.token else { return }
        do {
            try await SplashGAPI(token: token).unfollow(login)
            await auth.loadMe()
            await loadFollowing()
            await store.refresh(token: token)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
