import UIKit

enum ImageSaver {
    /// Download the full-resolution file (with CDN backup fallback) and
    /// write it to the photo library.
    static func save(_ photo: Photo) async throws {
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: photo.fullURL)
        } catch {
            guard let backup = photo.backupFullURL else { throw error }
            (data, _) = try await URLSession.shared.data(from: backup)
        }
        guard let image = UIImage(data: data) else {
            throw APIError(status: 0, message: "Could not decode image")
        }
        await MainActor.run {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }
}
