import SwiftUI
import Kingfisher

@main
struct SplashGApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var store = GalleryStore()

    init() {
        // Gallery repos serve immutable image files off CDN — cache hard.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024)
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 128 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 1024 * 1024 * 1024
        KingfisherManager.shared.downloader.downloadTimeout = 30
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
