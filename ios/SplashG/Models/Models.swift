import Foundation
import CoreGraphics

// MARK: - GitHub API models

struct GHUser: Codable {
    let login: String
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login, name
        case avatarUrl = "avatar_url"
    }
}

struct GHRepo: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let isPrivate: Bool
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case fullName = "full_name"
        case isPrivate = "private"
    }
}

struct GHRepoDetail: Codable {
    let defaultBranch: String
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
        case isPrivate = "private"
    }
}

struct GHTreeEntry: Codable {
    let path: String
    let type: String  // "blob" | "tree"
}

struct GHTreeResponse: Codable {
    let tree: [GHTreeEntry]
    let truncated: Bool
}

// MARK: - SplashG backend models (worker/src/index.ts shapes)

struct RepoBinding: Codable, Hashable, Identifiable {
    let repo: String     // "owner/name"
    let title: String?
    let addedAt: Int64?

    var id: String { repo }
    var displayTitle: String { title ?? repo.split(separator: "/").last.map(String.init) ?? repo }
}

struct MeProfile: Codable {
    let login: String
    let name: String?
    let avatarUrl: String?
    var repos: [RepoBinding]
    var following: [String]
    let followerCount: Int
}

struct FeedUser: Codable, Identifiable, Hashable {
    let login: String
    let name: String?
    let avatarUrl: String?
    let isMe: Bool?
    let repos: [RepoBinding]

    var id: String { login }
    var displayName: String { name ?? login }
}

struct UserProfile: Codable {
    let login: String
    let name: String?
    let avatarUrl: String?
    let repos: [RepoBinding]
    let followerCount: Int
    let followedByMe: Bool
}

// MARK: - Gallery domain models (album_template repo format)

struct GalleryConfig {
    var title: String?
    var baseURL: String
    var thumbnailURL: String
    var backupBaseURL: String?
    var backupThumbnailURL: String?
    var siteURL: String?
}

struct GeoPoint: Hashable {
    let latitude: Double
    let longitude: Double
}

struct Photo: Identifiable, Hashable {
    let repo: String        // "owner/name"
    let curator: String     // SplashG login the repo is bound to
    let albumTitle: String
    let albumSlug: String
    let filename: String    // on-disk name, e.g. "DSCF6070.webp"
    let thumbURL: URL
    let fullURL: URL
    let backupThumbURL: URL?
    let backupFullURL: URL?

    var id: String { repo + "/" + albumSlug + "/" + filename }
    var name: String { (filename as NSString).deletingPathExtension }

    /// Stable pseudo aspect ratio (w/h) for the masonry layout. Real
    /// dimensions aren't in the manifest, so derive a deterministic value
    /// from the id — cards keep their size across reloads.
    var aspect: CGFloat {
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return 0.68 + CGFloat(h % 62) / 100.0   // 0.68 ... 1.29
    }
}

struct Album: Identifiable, Hashable {
    let repo: String
    let curator: String
    let curatorName: String?
    let title: String
    let slug: String
    let date: Date?
    let dateString: String?
    let style: String?
    let subtitle: String?
    let coverThumbURL: URL?
    let coverFullURL: URL?
    let location: GeoPoint?
    var photos: [Photo]

    var id: String { repo + "/" + slug }
}

struct Gallery: Identifiable {
    let repo: String
    let curator: String
    let curatorName: String?
    let config: GalleryConfig
    var albums: [Album]

    var id: String { repo }
}

// MARK: - Errors

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}
