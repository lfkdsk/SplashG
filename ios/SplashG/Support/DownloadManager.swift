import SwiftUI
import UIKit

/// A photo saved into the app's own storage (Application Support/Downloads).
/// Files stay under our control (offline browsing, wallpaper flow) instead
/// of going straight to the system photo library.
struct DownloadItem: Codable, Identifiable, Hashable {
    let id: String            // Photo.id ("owner/name/album/file")
    let repo: String
    let curator: String
    let albumTitle: String
    let albumSlug: String
    let filename: String
    let relativePath: String  // under the downloads dir
    let downloadedAt: Date

    var name: String { (filename as NSString).deletingPathExtension }
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var inFlight: Set<String> = []

    private let fm = FileManager.default

    private var baseDir: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
    }
    private var indexURL: URL { baseDir.appendingPathComponent("index.json") }

    init() {
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            // Drop entries whose file vanished (reinstall, manual cleanup).
            items = decoded.filter { fm.fileExists(atPath: fileURL(for: $0).path) }
        }
    }

    func fileURL(for item: DownloadItem) -> URL {
        baseDir.appendingPathComponent(item.relativePath)
    }

    func item(for photo: Photo) -> DownloadItem? {
        items.first { $0.id == photo.id }
    }

    func isDownloaded(_ photo: Photo) -> Bool { item(for: photo) != nil }
    func isDownloading(_ photo: Photo) -> Bool { inFlight.contains(photo.id) }

    /// Fetch the full-resolution file (with CDN backup fallback) into app
    /// storage and index it. Idempotent per photo.
    func download(_ photo: Photo) async throws {
        guard !isDownloaded(photo), !inFlight.contains(photo.id) else { return }
        inFlight.insert(photo.id)
        defer { inFlight.remove(photo.id) }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: photo.fullURL)
        } catch {
            guard let backup = photo.backupFullURL else { throw error }
            (data, _) = try await URLSession.shared.data(from: backup)
        }

        let relative = "\(photo.repo)/\(photo.albumSlug)/\(photo.filename)"
        let dest = baseDir.appendingPathComponent(relative)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dest)

        items.insert(DownloadItem(
            id: photo.id, repo: photo.repo, curator: photo.curator,
            albumTitle: photo.albumTitle, albumSlug: photo.albumSlug,
            filename: photo.filename, relativePath: relative,
            downloadedAt: Date()), at: 0)
        persist()
    }

    func delete(_ item: DownloadItem) {
        try? fm.removeItem(at: fileURL(for: item))
        items.removeAll { $0.id == item.id }
        persist()
    }

    /// Export to the system photo library — the handoff point for setting
    /// a wallpaper (iOS offers no API to set wallpapers directly).
    func saveToPhotos(_ item: DownloadItem) throws {
        guard let image = UIImage(contentsOfFile: fileURL(for: item).path) else {
            throw APIError(status: 0, message: "Could not load downloaded file")
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: indexURL)
        }
    }
}
