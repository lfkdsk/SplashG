import Foundation
import SwiftUI

/// Loads and holds every gallery visible to the signed-in user:
/// worker `/feed` → (me + followees) with bound repos → per-repo
/// CONFIG.yml + README.yml + git tree from GitHub → albums/photos.
@MainActor
final class GalleryStore: ObservableObject {
    @Published var feedUsers: [FeedUser] = []
    @Published var galleries: [String: Gallery] = [:]   // key: "owner/name"
    @Published var loading = false
    @Published var backendError: String?
    @Published var galleryErrors: [String: String] = [:]
    @Published var lastRefresh: Date?

    // MARK: Derived collections

    var albums: [Album] {
        galleries.values.flatMap(\.albums)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var feedPhotos: [Photo] {
        albums.flatMap(\.photos)
    }

    func randomPhotos(_ count: Int) -> [Photo] {
        let all = feedPhotos
        guard all.count > count else { return all.shuffled() }
        return Array(all.shuffled().prefix(count))
    }

    var isEmpty: Bool { galleries.isEmpty }

    // MARK: Loading

    private var inFlightRefresh: Task<Void, Never>?

    func refreshIfStale(token: String) async {
        if let last = lastRefresh, Date().timeIntervalSince(last) < 300, !galleries.isEmpty { return }
        await refresh(token: token)
    }

    /// Deduplicates concurrent refreshes: a pull-to-refresh during an
    /// ongoing load waits for that load instead of silently no-opping.
    private func dedupe(_ work: @escaping () async -> Void) async {
        if let existing = inFlightRefresh {
            await existing.value
            return
        }
        let task = Task { await work() }
        inFlightRefresh = task
        await task.value
        inFlightRefresh = nil
    }

    /// Demo mode: load one public repo unauthenticated, no backend.
    func refreshDemo(repo: String) async {
        await dedupe { await self.performRefreshDemo(repo: repo) }
    }

    private func performRefreshDemo(repo: String) async {
        loading = true
        defer { loading = false }
        let owner = repo.split(separator: "/").first.map(String.init) ?? repo
        do {
            galleries[repo] = try await Self.loadGallery(
                token: nil, repo: repo, curator: owner, curatorName: nil)
        } catch {
            galleryErrors[repo] = error.localizedDescription
        }
        lastRefresh = Date()
    }

    func refresh(token: String) async {
        await dedupe { await self.performRefresh(token: token) }
    }

    private func performRefresh(token: String) async {
        loading = true
        defer { loading = false }

        do {
            feedUsers = try await SplashGAPI(token: token).feed()
            backendError = nil
        } catch {
            backendError = error.localizedDescription
            // Backend down: keep whatever we already had.
            if feedUsers.isEmpty {
                lastRefresh = Date()
                return
            }
        }

        let jobs: [(FeedUser, RepoBinding)] = feedUsers.flatMap { user in
            user.repos.map { (user, $0) }
        }
        let wanted = Set(jobs.map { $0.1.repo })

        // Drop galleries for repos that are no longer bound.
        galleries = galleries.filter { wanted.contains($0.key) }
        galleryErrors = [:]

        await withTaskGroup(of: (String, Result<Gallery, Error>).self) { group in
            for (user, binding) in jobs {
                group.addTask {
                    do {
                        let gallery = try await Self.loadGallery(
                            token: token, repo: binding.repo,
                            curator: user.login, curatorName: user.name)
                        return (binding.repo, .success(gallery))
                    } catch {
                        return (binding.repo, .failure(error))
                    }
                }
            }
            for await (repo, result) in group {
                switch result {
                case .success(let gallery): galleries[repo] = gallery
                case .failure(let error): galleryErrors[repo] = error.localizedDescription
                }
            }
        }
        lastRefresh = Date()
    }

    nonisolated private static func loadGallery(token: String?,
                                                repo: String,
                                                curator: String,
                                                curatorName: String?) async throws -> Gallery {
        let gh = GitHubAPI(token: token)
        let detail = try await gh.repoDetail(repo)
        let branch = detail.defaultBranch

        async let configText = gh.fileText(repo: repo, path: "CONFIG.yml", ref: branch)
        async let readmeText = gh.fileText(repo: repo, path: "README.yml", ref: branch)
        async let treeEntries = gh.tree(repo: repo, ref: branch)

        let config = GalleryParser.parseConfig(try await configText, repo: repo)
        let albums = GalleryParser.parseAlbums(
            readme: try await readmeText, config: config,
            repo: repo, curator: curator, curatorName: curatorName,
            tree: try await treeEntries)

        return Gallery(repo: repo, curator: curator, curatorName: curatorName,
                       config: config, albums: albums)
    }

    func clear() {
        feedUsers = []
        galleries = [:]
        galleryErrors = [:]
        backendError = nil
        lastRefresh = nil
    }
}
