import Foundation
import Yams

/// Parses the album_template repo contract:
///   CONFIG.yml  — CDN URL bases (base_url / thumbnail_url + backups)
///   README.yml  — album manifest keyed by display title
///   git tree    — actual photo files per album directory
enum GalleryParser {

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "avif"]

    // MARK: CONFIG.yml

    static func parseConfig(_ yaml: String, repo: String) -> GalleryConfig {
        let dict = (try? Yams.load(yaml: yaml)) as? [AnyHashable: Any] ?? [:]
        func str(_ key: String) -> String? {
            (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Sensible fallbacks mirror what build.py would use for this repo.
        let base = str("base_url") ?? "https://cdn.jsdelivr.net/gh/\(repo)@master"
        let thumb = str("thumbnail_url") ?? "https://cdn.jsdelivr.net/gh/\(repo)@thumbnail"
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        let rawBase = parts.count == 2 ? "https://raw.githubusercontent.com/\(parts[0])/\(parts[1])" : nil
        return GalleryConfig(
            title: str("title"),
            baseURL: base,
            thumbnailURL: thumb,
            backupBaseURL: str("backup_base_url") ?? rawBase.map { "\($0)/master" },
            backupThumbnailURL: str("backup_thumbnail_url") ?? rawBase.map { "\($0)/thumbnail" },
            siteURL: str("url"))
    }

    // MARK: README.yml + tree -> albums

    static func parseAlbums(readme: String,
                            config: GalleryConfig,
                            repo: String,
                            curator: String,
                            curatorName: String?,
                            tree: [GHTreeEntry]) -> [Album] {
        guard let manifest = (try? Yams.load(yaml: readme)) as? [AnyHashable: Any] else { return [] }

        // Group photo blobs by their top-level directory once.
        var filesByDir: [String: [String]] = [:]
        for entry in tree where entry.type == "blob" {
            let parts = entry.path.split(separator: "/")
            guard parts.count == 2 else { continue }  // photos sit directly inside the album dir
            let ext = (String(parts[1]) as NSString).pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            filesByDir[String(parts[0]), default: []].append(String(parts[1]))
        }

        var albums: [Album] = []
        for (rawKey, rawValue) in manifest {
            guard let title = (rawKey.base as? String)?.trimmingCharacters(in: .whitespaces),
                  let info = rawValue as? [AnyHashable: Any] else { continue }
            func field(_ key: String) -> Any? { info[key] }
            guard let slug = (field("url") as? String)?.trimmingCharacters(in: .whitespaces),
                  !slug.isEmpty else { continue }
            if field("hidden") as? Bool == true { continue }

            let (date, dateString) = parseDate(field("date"))
            let style = field("style") as? String
            let subtitle = field("subtitle") as? String
            let coverPath = field("cover") as? String
            let location = parseLocation(field("location"))

            let filenames = (filesByDir[slug] ?? []).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            let photos = filenames.compactMap { filename -> Photo? in
                let base = (filename as NSString).deletingPathExtension
                guard let thumb = joinURL(config.thumbnailURL, [slug, base + ".webp"]),
                      let full = joinURL(config.baseURL, [slug, filename]) else { return nil }
                return Photo(
                    repo: repo, curator: curator, albumTitle: title, albumSlug: slug,
                    filename: filename,
                    thumbURL: thumb, fullURL: full,
                    backupThumbURL: config.backupThumbnailURL.flatMap { joinURL($0, [slug, base + ".webp"]) },
                    backupFullURL: config.backupBaseURL.flatMap { joinURL($0, [slug, filename]) })
            }
            guard !photos.isEmpty else { continue }

            // Cover: extension is swapped for .webp on the thumbnail branch
            // (build.py does the same), full-size keeps the original file.
            var coverThumb: URL?
            var coverFull: URL?
            if let coverPath, !coverPath.isEmpty {
                let noExt = (coverPath as NSString).deletingPathExtension
                coverThumb = joinURL(config.thumbnailURL, (noExt + ".webp").split(separator: "/").map(String.init))
                coverFull = joinURL(config.baseURL, coverPath.split(separator: "/").map(String.init))
            }
            if coverThumb == nil { coverThumb = photos.first?.thumbURL }
            if coverFull == nil { coverFull = photos.first?.fullURL }

            albums.append(Album(
                repo: repo, curator: curator, curatorName: curatorName,
                title: title, slug: slug,
                date: date, dateString: dateString,
                style: style, subtitle: subtitle,
                coverThumbURL: coverThumb, coverFullURL: coverFull,
                location: location, photos: photos))
        }

        return albums.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // MARK: Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// README.yml dates are usually quoted strings; unquoted ones may come
    /// out of Yams as Date already.
    private static func parseDate(_ value: Any?) -> (Date?, String?) {
        if let d = value as? Date {
            return (d, dateFormatter.string(from: d))
        }
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            return (dateFormatter.date(from: trimmed), trimmed)
        }
        return (nil, nil)
    }

    private static func parseLocation(_ value: Any?) -> GeoPoint? {
        guard let arr = value as? [Any], arr.count == 2 else { return nil }
        func num(_ v: Any) -> Double? {
            (v as? Double) ?? (v as? Int).map(Double.init)
        }
        guard let lat = num(arr[0]), let lon = num(arr[1]), lat != 0 || lon != 0 else { return nil }
        return GeoPoint(latitude: lat, longitude: lon)
    }

    /// Join CDN base + path segments with per-segment percent-encoding —
    /// album dirs and filenames are frequently CJK.
    static func joinURL(_ base: String, _ segments: [String]) -> URL? {
        var b = base
        while b.hasSuffix("/") { b.removeLast() }
        let encoded = segments.compactMap {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        }
        guard encoded.count == segments.count else { return nil }
        return URL(string: b + "/" + encoded.joined(separator: "/"))
    }
}
