import SwiftUI

/// First-run step after sign-in: pick which of your GitHub repos are
/// album_template galleries and bind them to your SplashG profile.
/// Shown only while the account has no bindings; skippable.
struct OnboardingView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: GalleryStore

    @State private var repos: [GHRepo] = []
    @State private var loading = true
    @State private var filter = ""
    @State private var busyRepo: Int?
    @State private var bound: Set<String> = []
    @State private var errorMessage: String?
    @State private var finishing = false

    private var filtered: [GHRepo] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return repos }
        return repos.filter { $0.fullName.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.titleGradient)
                Text("Bind your galleries")
                    .font(.title2.bold())
                Text("Pick the repos that hold your album_template galleries — they become your albums on SplashG. You can add more later from Profile.")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 28)
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.subtle)
                TextField("Filter repos", text: $filter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.card))
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { repo in
                        repoRow(repo)
                    }
                    if !loading && filtered.isEmpty {
                        Text("No repos found")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtle)
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 20)
            }
            .overlay { if loading { ProgressView() } }

            Button(action: finish) {
                Text(finishing ? "Loading…" : (bound.isEmpty ? "Skip for now" : "Continue"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(bound.isEmpty ? Theme.card : Theme.accent))
                    .foregroundStyle(.white)
            }
            .disabled(finishing)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
    }

    private func repoRow(_ repo: GHRepo) -> some View {
        let isBound = bound.contains(repo.fullName)
        return Button {
            guard !isBound, busyRepo == nil else { return }
            Task { await bind(repo) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let desc = repo.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(Theme.subtle)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if busyRepo == repo.id {
                    ProgressView().controlSize(.small)
                } else if isBound {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Theme.accent)
                }
                if repo.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.subtle)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        defer { loading = false }
        guard let token = auth.token else { return }
        do {
            repos = try await GitHubAPI(token: token).repos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bind(_ repo: GHRepo) async {
        guard let token = auth.token else { return }
        busyRepo = repo.id
        errorMessage = nil
        defer { busyRepo = nil }
        do {
            try await SplashGAPI(token: token).bind(repo: repo.fullName, title: nil)
            bound.insert(repo.fullName)
        } catch {
            errorMessage = "\(repo.fullName): \(error.localizedDescription)"
        }
    }

    private func finish() {
        finishing = true
        Task {
            await auth.loadMe()
            auth.finishOnboarding()
            if let token = auth.token {
                await store.refresh(token: token)
            }
            finishing = false
        }
    }
}
